local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
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
  'prometheus-rules': rules,
}
