import 'package:open_rest/core/model/model.dart';

/// Pages of the collection / folder settings dialog.
enum NodeSection {
  general('General'),
  headers('Headers'),
  auth('Auth'),
  variables('Variables'),
  scripts('Scripts'),
  tests('Tests'),
  docs('Docs'),
  tls('TLS / Certificates');

  const NodeSection(this.label);
  final String label;
}

/// One-line description of how the page's settings reach requests.
String sectionHint(NodeSection s, {required bool isCol}) {
  final where = isCol ? 'collection' : 'folder';
  return switch (s) {
    NodeSection.general => 'About this $where.',
    NodeSection.headers => 'Sent with every request in this $where.',
    NodeSection.auth =>
      isCol
          ? 'Used by every request in this collection that inherits its auth.'
          : 'Used by requests in this folder that inherit their auth; "Inherit" falls back to the parent.',
    NodeSection.variables =>
      'Set before (pre request) or after (post response) every request in this $where.',
    NodeSection.scripts =>
      'Run around every request in this $where, before the request\'s own scripts.',
    NodeSection.tests => 'Assertions run after every request in this $where.',
    NodeSection.docs => 'Notes about this $where, shown to your team.',
    NodeSection.tls =>
      isCol ? 'Client certificate used for every request in this collection.' : 'Client certificate for requests in this folder; overrides the collection.',
  };
}

bool _named(KV k) => k.enabled && k.name.trim().isNotEmpty;

/// Dot used for "has content" badges.
const String dotBadge = '●';

/// Short text shown next to a navigation row, or null when nothing is configured.
String? sectionBadge(NodeSection s, NodeConfig c) {
  switch (s) {
    case NodeSection.general:
      return null;
    case NodeSection.headers:
      final n = c.headers.where(_named).length;
      return n == 0 ? null : '$n';
    case NodeSection.auth:
      return switch (c.auth.mode) {
        AuthMode.None || AuthMode.Inherit => null,
        AuthMode.Basic => 'Basic',
        AuthMode.Bearer => 'Bearer',
        AuthMode.ApiKey => 'API Key',
        AuthMode.Digest => 'Digest',
        AuthMode.OAuth2 => 'OAuth2',
      };
    case NodeSection.variables:
      final n =
          c.preVars.where(_named).length + c.postVars.where(_named).length;
      return n == 0 ? null : '$n';
    case NodeSection.scripts:
      return c.preScript.trim().isEmpty && c.postScript.trim().isEmpty
          ? null
          : dotBadge;
    case NodeSection.tests:
      return c.tests.trim().isEmpty ? null : dotBadge;
    case NodeSection.docs:
      return c.docs.trim().isEmpty ? null : dotBadge;
    case NodeSection.tls:
      return switch (c.tls.mode) {
        TlsMode.inherit => null,
        TlsMode.none => 'None',
        TlsMode.custom => c.tls.format == TlsFormat.pfx ? 'PFX' : 'PEM',
      };
  }
}

/// Whether the draft differs from what is saved.
bool nodeConfigDirty(NodeConfig saved, NodeConfig draft) => saved != draft;

/// Item counts below a collection or folder.
class NodeStats {
  const NodeStats({this.requests = 0, this.folders = 0});
  final int requests;
  final int folders;

  @override
  bool operator ==(Object other) =>
      other is NodeStats &&
      other.requests == requests &&
      other.folders == folders;

  @override
  int get hashCode => Object.hash(requests, folders);
}

/// Counts requests and folders anywhere below [nodes].
NodeStats nodeStats(List<Node> nodes) {
  var r = 0, f = 0;
  for (final n in nodes) {
    if (n is RequestNode) {
      r++;
    } else if (n is FolderNode) {
      f++;
      final s = nodeStats(n.children);
      r += s.requests;
      f += s.folders;
    }
  }
  return NodeStats(requests: r, folders: f);
}

/// The folder at [path] anywhere in [nodes].
FolderNode? findFolder(List<Node> nodes, String path) {
  for (final n in nodes) {
    if (n is FolderNode) {
      if (n.path == path) return n;
      final r = findFolder(n.children, path);
      if (r != null) return r;
    }
  }
  return null;
}

/// "3 requests", "1 folder".
String countLabel(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
