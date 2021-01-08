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

local monitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: 'rancher-federation',
    namespace: namespace,
  },
  spec: {
    namespaceSelector: {
      matchNames: [
        'cattle-prometheus',
      ],
    },
    selector: {
      matchLabels: {
        app: 'prometheus',
      },
    },
    endpoints: [
      {
        port: 'nginx-http',
        interval: federation_interval,
        scrapeTimeout: federation_scrape_timeout,
        path: '/federate',
        params: {
          'match[]': [
            '{job!=""}',
          ],
        },
        honorLabels: true,
      },
    ],
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
  monitor,
  rule,
]
