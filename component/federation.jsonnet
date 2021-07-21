local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = params.namespace;

local prometheus_instance = params.prometheusInstance;
local federation_interval = params.federation.interval;
// "interval" and "scrape_timeout" are strings, so we can't do any meaningful
// comparison/sanity checks without parsing them, which would be overkill.
local federation_scrape_timeout = params.federation.scrape_timeout;

local scrape_config = kube.Secret('additional-scrape-configs') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'prometheus-additional.yaml': std.manifestYamlDoc([
      {
        job_name: 'access-prometheus',
        honor_labels: true,
        honor_timestamps: true,
        params: {
          'match[]': [
            '{job!="ingress-nginx-controller-metrics",created_by_kind!="nginx-ingress-controller"}',
          ],
        },
        scrape_interval: federation_interval,
        scrape_timeout: federation_scrape_timeout,
        metrics_path: '/federate',
        scheme: 'http',
        static_configs: [
          {
            targets: [
              params.federation_target,
            ],
          },
        ],
        metric_relabel_configs: [
          // drop unneeded `prometheus_replica` label from federated metrics
          {
            action: 'labeldrop',
            regex: 'prometheus_replica',
          },
          // Fix broken namespace labels on "expose-kubelets-metrics" metrics
          // federated from Rancher Prometheus.
          // The following actions replace the value of the namespace label
          // with the value of the exported_namespace label if both exist for
          // a metric.
          {
            action: 'replace',
            source_labels: [ 'namespace' ],
            target_label: '__tmp_namespace',
          },
          {
            action: 'labeldrop',
            regex: 'namespace',
          },
          // replace value of label namespace with value of label
          // exported_namespace if label namespace contained
          // "cattle-prometheus".
          {
            action: 'replace',
            regex: 'cattle-prometheus;(.*)',
            replacement: '$1',
            source_labels: [
              '__tmp_namespace',
              'exported_namespace',
            ],
            target_label: 'namespace',
          },
          // Put back original namespace label otherwise.
          {
            action: 'replace',
            source_labels: [
              'exported_namespace',
              '__tmp_namespace',
            ],
            regex: ';(.*)',
            replacement: '$1',
            target_label: 'namespace',
          },
          {
            action: 'labeldrop',
            regex: '(__tmp|exported)_namespace',
          },
        ],
      },
    ]),
  },
};

local rule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'rancher-federation',
    namespace: namespace,
    labels: {
      prometheus: prometheus_instance,
      role: 'alert-rules',
    },
  },
  spec: {
    groups: [ {
      name: 'rancher-federation',
      rules: [ {
        alert: 'rancher_federation_down',
        expr: 'min_over_time(up{job="access-prometheus"}[1m]) == 0',
        'for': '180s',
        labels: {
          severity: 'critical',
        },
        annotations: {
          message: 'Scraping metrics from Rancher cluster monitoring is failing.',
        },
      } ],
    } ],
  },
};


[
  scrape_config,
  rule,
]
