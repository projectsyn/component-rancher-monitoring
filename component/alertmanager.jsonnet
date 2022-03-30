local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rancher_monitoring;
local namespace = params.namespace;
local instance = params.alertmanagerInstance;
local name = 'alertmanager-' + instance;

local labels = {
  'app.kubernetes.io/name': 'alertmanager',
  'app.kubernetes.io/instance': instance,
  'app.kubernetes.io/managed-by': 'syn',
};

local matchLabels = {
  prometheus: instance,
  role: 'alert-rules',
};

local sa = kube.ServiceAccount(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
};

local alertmanager = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'Alertmanager',
  metadata: {
    name: instance,
    namespace: namespace,
    labels: labels,
  },
  spec+: {
    image: params.images.alertmanager.image + ':' + params.images.alertmanager.tag,
    nodeSelector+: {
      'kubernetes.io/os': 'linux',
    },
    securityContext+: {
      fsGroup: 2000,
      runAsNonRoot: true,
      runAsUser: 1000,
    },
    serviceAccountName: sa.metadata.name,
  } + com.makeMergeable(params.alertmanager),
};

local service = kube.Service(name) {
  metadata+: {
    namespace: params.namespace,
    labels+: labels,
  },
  spec+: {
    ports: [
      {
        name: 'web',
        port: 9093,
        targetPort: 'web',
      },
    ],
    selector: labels,
    sessionAffinity: 'ClientIP',
  },
};

local servicemonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: name,
    namespace: namespace,
    labels: matchLabels,
  },
  spec: {
    endpoints: [
      {
        interval: '30s',
        port: 'web',
      },
    ],
    selector: {
      app: 'alertmanager',
      alertmanager: name,
    },
  },
};

local secret = kube.Secret(name) {
  metadata+: {
    namespace: namespace,
    labels+: labels,
  },
  stringData: {
    // TODO: consider sanitizing or verifying input config
    'alertmanager.yaml': std.manifestYamlDoc(params.alertmanagerConfig),
  },
};

[ alertmanager, sa, service, servicemonitor, secret ]
