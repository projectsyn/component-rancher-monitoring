local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local ignoreNames = params.alerts.ignoreNames;
local customAnnotations = params.alerts.customAnnotations;
local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};


local patchNodeFilesystemRules(rule) =
  local nodeFsRules = std.set([
    'NodeFilesystemSpaceFillingUp',
    'NodeFilesystemAlmostOutOfSpace',
    'NodeFilesystemFilesFillingUp',
    'NodeFilesystemAlmostOutOfFiles',
  ]);
  rule {
    expr:
      if std.setMember(rule.alert, nodeFsRules) then
        'bottomk by (device, host_ip) (1, %s)' % rule.expr
      else
        rule.expr,
  };

local patchPersistentVolumeRules(rule) =
  local pvRules = std.set([
    'KubePersistentVolumeUsageCritical',
    'KubePersistentVolumeFullInFourDays',
    'KubePersistentVolumeFillingUp',
  ]);
  rule {
    expr:
      if std.setMember(rule.alert, pvRules) then
        // This will first deduplicate the available space per persistent volume  by taking the minimum grouped by pvc-name and namespace
        // (Note: We explicitly use `min` and not `bottomk`. `bottomk` will produce duplicates if e.g. a RXO pod is recreated)
        // The deduplicated metric is then matched with `kube_persistentvolumeclaim_info' which is always one. We
        // do this by multiplying the two values.
        // `*on(persistentvolumeclaim, namespace)` will mutliply the metrics and pvc_info that match on pvc-name and namespace
        // `group_left(storageclass)` will add the storageclass label of the pvc_info to the resulting metric
        // `namespace` so that we are able to match the two metrics.
        // Finally it will filter out shared storage classes if they are configured
        (
          'min by (persistentvolumeclaim, namespace) (%s)'
          + '*on(persistentvolumeclaim, namespace) group_left(storageclass) kube_persistentvolumeclaim_info{storageclass!~"%s"}'
        ) % [ rule.expr, params.alerts.sharedStorageClass ]
      else
        rule.expr,
  };


local patchGeneralRules(rule) =
  if rule.alert == 'Watchdog' then
    rule {
      labels: {
        heartbeat: '60s',
        severity: 'critical',
      },
      annotations+: {
        description: 'This is a dead mans switch meant to ensure that the entire alerting pipeline is functional.',
        summary: 'Alerting dead mans switch',
      },
    }
  else
    rule;

local ruleAlter(group) =
  if group.name == 'general.rules' then
    group {
      rules: std.map(patchGeneralRules, group.rules),
    }
  else if group.name == 'node-exporter' then
    group {
      rules: std.map(patchNodeFilesystemRules, group.rules),
    }
  else if group.name == 'kubernetes-storage' then
    group {
      rules: std.map(patchPersistentVolumeRules, group.rules),
    }
  else
    group;


local alterRules = {
  prometheusAlerts+:: {
    groups: std.map(
      ruleAlter,
      super.groups
    ),
  },
};

local annotateAlertRules(rule) =
  // Only add custom annotations to alert rules, since recording
  // rules cannot have annotations.
  // We identify alert rules by the presence of the `alert` field.
  if std.objectHas(rule, 'alert') then
    local annotations =
      defaultAnnotations +
      if std.objectHas(customAnnotations, rule.alert) then
        customAnnotations[rule.alert]
      else
        {};

    rule {
      annotations+: annotations,
    }
  else
    rule;

local ruleAnnotate(group) =
  group {
    rules: std.map(annotateAlertRules, group.rules),
  };

local annotateRules = {
  prometheusAlerts+:: {
    groups: std.map(
      ruleAnnotate,
      super.groups
    ),
  },
};

local ruleFilter(group) =
  local internalRuleFilter =
    if group.name == 'kubernetes-apps' then
      [ 'KubeHpaMaxedOut', 'KubeHpaReplicasMismatch' ]
    else if group.name == 'kubernetes-resources' then
      [ 'CPUThrottlingHigh' ]
    else if group.name == 'kubernetes-system-apiserver' then
      // This can be removed once https://github.com/coreos/kube-prometheus/pull/516 got merged
      [ 'AggregatedAPIDown' ]
    else
      [];

  // merge user-provided and hard-coded rule names to filter out
  local ignoreSet = std.set(internalRuleFilter + params.alerts.ignoreNames);

  // return group object, with filtered rules list
  group {
    rules: std.filter(
      function(rule)
        // never filter rules which don't have the `alert` field, those are
        // probably recording rules.
        !std.objectHas(rule, 'alert') ||
        // filter out rules which are in our set of rules to ignore
        !std.member(ignoreSet, rule.alert),
      group.rules
    ),
  };

local filterRules = {
  prometheusAlerts+:: {
    groups: std.map(
      ruleFilter,
      super.groups
    ),
  },
};

local additionalRules = {
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'node-utilization',
        rules: [
          {
            alert: 'node_cpu_load5',
            expr: 'max by(instance) (node_load5) / count by(instance) (node_cpu_seconds_total{mode="idle"}) > 2',
            'for': '30m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              message: '{{$labels.instance}}: Load higher than (current value is: {{ $value }})',
            },
          },
          {
            alert: 'node_memory_free_percent',
            expr: '(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.97',
            'for': '30m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              message: '{{$labels.node}}: Memory usage more than 97% (current value is: {{ $value | humanizePercentage }})%',
            },
          },
        ],
      },
      {
        name: 'kubernetes-storage-class',
        rules: [
          {
            alert: 'KubeStorageClassFillingUp',
            // This will first calculate the persentage of available space for each PV mount and filter for all
            // that have less then 3% of available storage.
            // We then match the persistent volume usage with `kube_persistentvolumeclaim_info' which is always one. We
            // do this by multiplying the two values.
            // `*on(persistentvolumeclaim, namespace)` will mutliply the metrics and pvc_info that match on pvc-name and namespace
            // `group_left(storageclass)` will add the storageclass label of the pvc_info to the resulting metric
            // `namespace` so that we are able to match the two metrics.
            // It will filter only shared storage classes and take the minimum (They should all have the same available space)
            expr: (
              'min by (storageclass)'
              + '(kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.03'
              + '*on(persistentvolumeclaim, namespace) group_left(storageclass) kube_persistentvolumeclaim_info{storageclass="%s"})'
            ) % params.alerts.sharedStorageClass,
            'for': '1m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              message: 'The storage class {{ $labels.storageclass }} is only {{ $value | humanizePercentage }} free.',
              summary: 'StorageClass is filling up.',
            },
          },
          {
            alert: 'KubeStorageClassFillingUp',
            // This will first calculate the persentage of available space for each PV mount and filter for all
            // that have less then 15% of available storage. It will then predict the available space in four days
            // and filter for all metrics that are expected to run out of space.
            // We then match the persistent volume usage with `kube_persistentvolumeclaim_info' which is always one. We
            // do this by multiplying the two values.
            // `*on(persistentvolumeclaim, namespace)` will mutliply the metrics and pvc_info that match on pvc-name and namespace
            // `group_left(storageclass)` will add the storageclass label of the pvc_info to the resulting metric
            // `namespace` so that we are able to match the two metrics.
            // It will filter only shared storage classes and take the minimum (They should all have the same available space)
            expr: (
              'min by (storageclass) ('
              + '(kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.15'
              + 'and'
              + 'predict_linear(kubelet_volume_stats_available_bytes[6h], 4 * 24 * 3600) < 0)'
              + '*on(persistentvolumeclaim, namespace) group_left(storageclass) kube_persistentvolumeclaim_info{storageclass="%s"})'
            ) % params.alerts.sharedStorageClass,
            'for': '1h',
            labels: {
              severity: 'warning',
            },
            annotations: {
              message: (
                'Based on recent sampling, the storage class {{ $labels.storageclass }} is expected to fill up'
                + 'within four days. Currently {{ $value | humanizePercentage }} is available.'
              ),
              summary: 'StorageClass is filling up.',
            },
          },
        ],
      },
    ],
  },
};

local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  additionalRules +
  alterRules +
  annotateRules +
  filterRules +
  {
    _config+:: {
      namespace: params.namespace,

      prometheus+:: {
        name: params.prometheusInstance,
      },

      alertmanager+:: {
        name: params.alertmanagerInstance,
      },

      prometheusOperatorSelector: 'job="expose-operator-metrics",namespace="cattle-prometheus"',
      kubeApiserverSelector: 'job="kubernetes"',
      kubeStateMetricsSelector: 'job="expose-kubernetes-metrics"',
      kubeletSelector: 'job="expose-kubelets-metrics"',
      nodeExporterSelector: 'job="expose-node-metrics"',
      namespaceSelector: params.alerts.namespaceSelector,
    },
  };

kp.prometheus.rules
