local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local exclude_rules = params.exclude_rules;

local alterRules = {
  prometheusAlerts+:: {
    groups: std.map(
      function(group)
        if group.name == 'general.rules' then
          group {
            rules: std.map(
              function(rule)
                // Attach Signalilo/Icinga heartbeat labeling to Watchdog rule.
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
                  rule,
              group.rules
            ),
          }
        else
          group,
      super.groups
    ),
  },
};

local ruleFilter(group) =
  local internalRuleFilter =
    if group.name == 'kubernetes-apps' then
      ['KubeHpaMaxedOut', 'KubeHpaReplicasMismatch']
    else if group.name == 'kubernetes-resources' then
      ['CPUThrottlingHigh']
    else if group.name == 'kubernetes-system-apiserver' then
      // This can be removed once https://github.com/coreos/kube-prometheus/pull/516 got merged
      ['AggregatedAPIDown']
    else
      [];
  local userRuleFilter =
    [r.name for r in exclude_rules if r.group == group.name];

  # merge user-provided and hard-coded rule names to filter out
  std.set(internalRuleFilter + userRuleFilter);

local filterRules = {
  prometheusAlerts+:: {
    groups: std.map(
      function(group)
        group {
          rules: std.filter(
            function(rule)
              !std.member(ruleFilter(group), rule.alert),
            group.rules
          ),
        },
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
    ],
  },
};

local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  filterRules +
  alterRules +
  additionalRules +
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
      prefixedNamespaceSelector: 'namespace=~"default|((kube|syn|cattle).*)",',
    },
  };

kp.prometheus.rules
