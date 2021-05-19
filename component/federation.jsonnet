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
              'access-prometheus.cattle-prometheus.svc.cluster.local:80',
            ],
          },
        ],
        relabel_configs: [
          {
            regex: 'pod_name',
            action: 'labeldrop',
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
