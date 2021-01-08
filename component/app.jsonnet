local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('rancher-monitoring', params.namespace);

{
  'rancher-monitoring': app,
}
