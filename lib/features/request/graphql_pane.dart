import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/json.dart';

/// Body editor of a GraphQL request: toolbar (operation, prettify, docs), query and variables.
///
/// The schema browser opens as a floating menu from the Docs button.
class GraphqlBody extends StatelessWidget {
  const GraphqlBody({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  static const String _auto = 'Auto';

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = tab.draft;
    void upd(ApiRequest Function(ApiRequest) f) => state.update(tab, f);
    final ops = parseOperations(r.bodyGraphql);
    final names = [for (final o in ops) ?o.name];
    final showOp = names.length > 1 || r.operationName.isNotEmpty;
    final opSelected = r.operationName.isEmpty ? _auto : r.operationName;
    final varsBad =
        r.bodyGraphqlVars.trim().isNotEmpty &&
        Json.tryParse(r.bodyGraphqlVars) == null;

    final toolbar = Row(
      spacing: 8,
      children: [
        if (showOp) ...[
          T('Operation', color: pal.muted, size: 11),
          Dropdown(
            key: const ValueKey('gql-operation'),
            selected: opSelected,
            options: [
              _auto,
              if (r.operationName.isNotEmpty &&
                  !names.contains(r.operationName))
                r.operationName,
              ...names,
            ],
            onSelect: (v) =>
                upd((it) => it.copyWith(operationName: v == _auto ? '' : v)),
          ),
        ],
        Btn(
          key: const ValueKey('gql-prettify-query'),
          label: 'Prettify',
          icon: Ic.edit,
          onClick: () => upd(
            (it) => it.copyWith(bodyGraphql: prettifyQuery(it.bodyGraphql)),
          ),
        ),
        const Spacer(),
        Builder(
          builder: (anchorCtx) => Btn(
            key: const ValueKey('gql-docs-toggle'),
            label: tab.gqlSchema == null ? 'Docs' : 'Docs ✓',
            icon: Ic.docs,
            onClick: () => _openDocs(anchorCtx, upd),
          ),
        ),
      ],
    );

    final editors = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        const SectionLabel('QUERY'),
        Expanded(
          flex: 14,
          child: CodeEditor(
            value: r.bodyGraphql,
            onChange: (v) => upd((it) => it.copyWith(bodyGraphql: v)),
            lang: 'graphql',
            placeholder: 'query {\n  viewer { id }\n}',
            showStatus: true,
            scrollbar: true,
          ),
        ),
        Row(
          children: [
            const SectionLabel('VARIABLES (JSON)'),
            if (varsBad)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: T(
                  'Invalid JSON, sent as {}',
                  key: const ValueKey('gql-vars-error'),
                  color: pal.err,
                  size: 11,
                ),
              ),
            const Spacer(),
            Btn(
              label: 'Prettify',
              onClick: () {
                final v = Json.prettyText(r.bodyGraphqlVars);
                if (v != null) {
                  upd((it) => it.copyWith(bodyGraphqlVars: v));
                } else {
                  state.showToast('Variables are not valid JSON');
                }
              },
              icon: Ic.edit,
            ),
          ],
        ),
        Expanded(
          flex: 10,
          child: CodeEditor(
            value: r.bodyGraphqlVars,
            onChange: (v) => upd((it) => it.copyWith(bodyGraphqlVars: v)),
            lang: 'json',
            scrollbar: true,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        toolbar,
        Expanded(child: editors),
      ],
    );
  }

  /// Opens the schema browser as a floating menu under the Docs button.
  void _openDocs(
    BuildContext anchorCtx,
    void Function(ApiRequest Function(ApiRequest)) upd,
  ) {
    final h = MediaQuery.sizeOf(anchorCtx).height;
    showAnchoredPopup<void>(
      anchorCtx,
      anchor: anchorRectOf(anchorCtx),
      width: 400,
      radius: 8,
      offset: const Offset(0, 4),
      builder: (ctx, close) => SizedBox(
        height: (h * 0.7).clamp(320.0, 560.0),
        child: ListenableBuilder(
          listenable: tab,
          builder: (context, _) => GraphqlDocs(
            state: state,
            tab: tab,
            onClose: () => close(),
            onInsert: (snippet, root) => upd(
              (it) => it.copyWith(
                bodyGraphql: insertField(it.bodyGraphql, snippet, root: root),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The schema browser (shown in a floating menu): fetch / loading / error states, then a searchable browser.
/// Tapping a field inserts it into the query and keeps the menu open.
class GraphqlDocs extends StatefulWidget {
  const GraphqlDocs({
    super.key,
    required this.state,
    required this.tab,
    required this.onInsert,
    required this.onClose,
  });

  final AppState state;
  final RequestTab tab;

  /// Called with the text to insert and the operation keyword of the root it came from.
  final void Function(String snippet, String root) onInsert;

  /// Dismisses the floating menu.
  final VoidCallback onClose;

  @override
  State<GraphqlDocs> createState() => _GraphqlDocsState();
}

class _GraphqlDocsState extends State<GraphqlDocs> {
  /// Type names navigated into; empty shows the roots.
  final List<String> _stack = [];
  String _q = '';

  RequestTab get tab => widget.tab;

  /// Operation keyword of the root the current view descends from (query when it did not start at a root).
  String _rootOf(GqlSchema s) {
    if (_stack.isEmpty) return 'query';
    if (_stack.first == s.mutation) return 'mutation';
    if (_stack.first == s.subscription) return 'subscription';
    return 'query';
  }

  String _named(String type) => type.replaceAll(RegExp(r'[\[\]!]'), '');

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final schema = tab.gqlSchema;
    return Container(
      key: const ValueKey('gql-docs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(pal, schema),
          Container(height: 1, color: pal.border),
          Expanded(child: schema == null ? _empty(pal) : _browser(pal, schema)),
        ],
      ),
    );
  }

  Widget _header(Pal pal, GqlSchema? schema) {
    final back = _stack.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        spacing: 6,
        children: [
          if (back)
            Clickable(
              key: const ValueKey('gql-docs-back'),
              onClick: () => setState(() {
                _stack.removeLast();
                _q = '';
              }),
              cursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Ico(Ic.chevronLeft, tint: pal.muted, size: 14),
              ),
            ),
          Expanded(
            child: back
                ? T(
                    _stack.last,
                    mono: true,
                    size: 12,
                    weight: FontWeight.w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : T(
                    schema == null
                        ? 'SCHEMA'
                        : 'SCHEMA · ${schema.visibleTypes.length} TYPES',
                    color: pal.muted,
                    size: 11,
                    weight: FontWeight.w600,
                  ),
          ),
          if (schema != null && !back)
            Clickable(
              key: const ValueKey('gql-schema-reload'),
              onClick: tab.gqlLoading
                  ? () {}
                  : () => widget.state.fetchGraphqlSchema(tab),
              cursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: tab.gqlLoading
                    ? SizedBox(
                        key: const ValueKey('gql-reload-spinner'),
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: pal.accent,
                          strokeWidth: 1.5,
                        ),
                      )
                    : Ico(Ic.refresh, tint: pal.muted, size: 14),
              ),
            ),
          Clickable(
            key: const ValueKey('gql-docs-close'),
            onClick: widget.onClose,
            cursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Ico(Ic.close, tint: pal.muted, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// No schema yet: loading, the error, or the button to fetch it.
  Widget _empty(Pal pal) {
    final hasUrl = tab.draft.url.trim().isNotEmpty;
    final err = tab.gqlError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (tab.gqlLoading) ...[
              SizedBox(
                key: const ValueKey('gql-schema-spinner'),
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: pal.accent,
                  strokeWidth: 3,
                ),
              ),
              T('Fetching schema…', color: pal.muted, size: 12),
            ] else ...[
              T(
                err == null ? 'No schema loaded' : 'Could not load the schema',
                weight: FontWeight.w600,
              ),
              if (err != null)
                T(
                  err,
                  key: const ValueKey('gql-schema-error'),
                  color: pal.err,
                  size: 11,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                )
              else
                T(
                  'Fetch the schema to browse types and insert fields.',
                  color: pal.muted,
                  size: 12,
                  textAlign: TextAlign.center,
                ),
              Btn(
                key: const ValueKey('gql-schema'),
                label: err == null ? 'Fetch schema' : 'Retry',
                enabled: hasUrl,
                onClick: () => widget.state.fetchGraphqlSchema(tab),
              ),
              if (!hasUrl) T('Enter the URL first', color: pal.muted, size: 11),
            ],
          ],
        ),
      ),
    );
  }

  Widget _browser(Pal pal, GqlSchema s) {
    final current = _stack.isEmpty ? null : s.types[_stack.last];
    final q = _q.trim().toLowerCase();
    bool matches(String name) => q.isEmpty || name.toLowerCase().contains(q);

    void open(String name) => setState(() {
      _stack.add(name);
      _q = '';
    });

    Widget row(
      Widget title,
      String sub, {
      VoidCallback? onTap,
      VoidCallback? onOpen,
      Key? key,
    }) => Clickable(
      key: key,
      onClick: onTap ?? () {},
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          spacing: 6,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (sub.isNotEmpty)
                    T(
                      sub,
                      color: pal.muted,
                      size: 11,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onOpen != null)
              Clickable(
                onClick: onOpen,
                cursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Ico(Ic.chevronRight, tint: pal.muted, size: 14),
                ),
              ),
          ],
        ),
      ),
    );

    Widget name(String t) => T(t, mono: true, size: 12);

    Widget fieldRow(GqlField f) {
      final t = s.types[f.typeName];
      final args = f.args.isEmpty
          ? ''
          : '(${f.args.map((a) => '${a.name}: ${a.type}').join(', ')})';
      return row(
        name(f.name),
        '$args: ${f.type}',
        onTap: () => widget.onInsert(s.skeleton(f), _rootOf(s)),
        onOpen: t != null && !t.isLeaf ? () => open(t.name) : null,
      );
    }

    final children = <Widget>[];
    if (current == null) {
      if (q.isEmpty) {
        for (final (label, root, t) in [
          ('Query', 'query', s.queryType),
          ('Mutation', 'mutation', s.mutationType),
          ('Subscription', 'subscription', s.subscriptionType),
        ]) {
          if (t == null) continue;
          children.add(
            row(
              T(label, weight: FontWeight.w600, size: 12),
              '${t.fields.length} fields',
              key: ValueKey('gql-root-$root'),
              onTap: () => open(t.name),
              onOpen: () => open(t.name),
            ),
          );
        }
      } else {
        children.addAll([
          for (final t in s.visibleTypes.where((t) => matches(t.name)).take(40))
            row(
              name(t.name),
              t.kind.toLowerCase().replaceAll('_', ' '),
              onTap: () => open(t.name),
            ),
        ]);
      }
    } else {
      children.addAll([
        for (final f in current.fields.where((f) => matches(f.name)))
          fieldRow(f),
        for (final a in current.inputFields.where((a) => matches(a.name)))
          row(
            name(a.name),
            a.type,
            onOpen: s.types[_named(a.type)] != null
                ? () => open(_named(a.type))
                : null,
          ),
        for (final e in current.enumValues.where(matches)) row(name(e), ''),
      ]);
    }
    if (children.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(14),
          child: T('Nothing matches "$_q"', color: pal.muted, size: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Field(
            key: ValueKey('gql-search-${_stack.length}'),
            value: _q,
            onChange: (v) => setState(() => _q = v),
            placeholder: _stack.isEmpty ? 'Find a type' : 'Filter',
            highlightVars: false,
          ),
        ),
        Container(height: 1, color: pal.border),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
