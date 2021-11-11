local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = inv.parameters.rancher_monitoring.namespace;

local alertmanager = import 'alertmanager.jsonnet';
local federation = import 'federation.jsonnet';
local prometheus = import 'prometheus.jsonnet';
local rules = import 'rules.jsonnet';

{
  '00_namespace': kube.Namespace(namespace) {
    metadata+: {
      labels+: {
        SYNMonitoring: 'main',
      },
    },
  },
  '01_prometheus': prometheus,
  '02_alertmanager': alertmanager,
  '10_federation': federation,
  'rules/00_kube-prometheus': rules,
} + {
  ['rules/' + group_name]: prom.PrometheusRule(group_name) {
    metadata+: {
      namespace: params.namespace,
      labels+: {
        prometheus: params.prometheusInstance,
        role: 'alert-rules',
      },
    },
    spec+: {
      groups+: [ {
        name: group_name,
        rules: [
          local rnamekey = std.splitLimit(rname, ':', 1);
          params.rules[group_name][rname] {
            [rnamekey[0]]: rnamekey[1],
          }
          for rname in std.objectFields(params.rules[group_name])
          if params.rules[group_name][rname] != null
        ],
      } ],
    },
  }
  for group_name in std.objectFields(params.rules)
  if params.rules[group_name] != null
}
