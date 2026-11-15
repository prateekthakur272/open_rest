import 'package:flutter/widgets.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/theme/theme.dart';

class _Tool {
  const _Tool(this.title, this.hint, this.add);
  final String title;
  final String hint;
  final VoidCallback add;
}

/// Dialog for choosing a step to add to the workflow.
class AddStepDialog extends StatefulWidget {
  const AddStepDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalAddStep m;

  @override
  State<AddStepDialog> createState() => _AddStepDialogState();
}

class _AddStepDialogState extends State<AddStepDialog> {
  String mode = 'Existing request';
  String filter = '';
  String name = '';
  String method = 'GET';
  String url = '{{baseUrl}}/';

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final state = widget.state, m = widget.m;
    RequestTab? tab;
    for (final t in state.tabs) {
      if (t.id == m.tabId) tab = t;
    }
    final col = tab == null ? null : state.collection(tab.collectionPath);
    if (tab == null || col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final tb = tab;
    final reqs = col.allRequests();
    final f = filter.trim().toLowerCase();
    final shown = reqs
        .where(
          (r) =>
              f.isEmpty ||
              r.name.toLowerCase().contains(f) ||
              r.request.url.toLowerCase().contains(f),
        )
        .toList();
    void done(VoidCallback fn) {
      fn();
      state.modal = null;
    }

    Widget body;
    switch (mode) {
      case 'Existing request':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Field(
              value: filter,
              onChange: (v) => setState(() => filter = v),
              placeholder: 'Filter requests…',
              highlightVars: false,
            ),
            if (reqs.isEmpty)
              T(
                'This collection has no requests yet. Use “New request”.',
                color: pal.muted,
              ),
            Expanded(
              child: ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final r = shown[i];
                  final folder = col
                      .ancestorFolders(r.path)
                      .map((x) => x.name)
                      .join(' / ');
                  return Clickable(
                    onClick: () => done(
                      () => state.addWorkflowStep(
                        tb,
                        r,
                        parent: m.parent,
                        branch: m.branch,
                      ),
                    ),
                    cursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: Row(
                        spacing: 10,
                        children: [
                          MethodPill(r.request.method),
                          Flexible(
                            flex: 0,
                            child: T(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: T(
                              [
                                folder,
                                r.request.url,
                              ].where((s) => s.isNotEmpty).join('  ·  '),
                              color: pal.muted,
                              size: 11,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      case 'New request':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const SectionLabel('NAME'),
            Field(
              value: name,
              onChange: (v) => setState(() => name = v),
              placeholder: 'e.g. Create order',
              highlightVars: false,
            ),
            const SectionLabel('METHOD AND URL'),
            Row(
              spacing: 8,
              children: [
                Dropdown(
                  selected: method,
                  options: HTTP_METHODS,
                  onSelect: (v) => setState(() => method = v),
                ),
                Expanded(
                  child: Field(
                    value: url,
                    onChange: (v) => setState(() => url = v),
                    placeholder: 'https://…',
                    mono: true,
                  ),
                ),
              ],
            ),
            T(
              'The request is saved in the collection, so you can refine its headers, body and scripts from the request tab.',
              color: pal.muted,
              size: 12,
            ),
            const Spacer(),
          ],
        );
      default:
        final tools = [
          _Tool(
            'If / else',
            'Run different steps depending on a condition, e.g. status is 200, or count is greater than 0.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.If,
              parent: m.parent,
              branch: m.branch,
            ),
          ),
          _Tool(
            'Loop over a list',
            'Repeat steps for every item of a list from a response — e.g. create an order line for each product.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Loop,
              parent: m.parent,
              branch: m.branch,
              loop: LoopMode.ForEach,
            ),
          ),
          _Tool(
            'Repeat N times',
            'Run steps a fixed number of times.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Loop,
              parent: m.parent,
              branch: m.branch,
              loop: LoopMode.Repeat,
            ),
          ),
          _Tool(
            'Repeat while…',
            'Keep going while a condition is true (with a safety limit) — e.g. poll until a status says “done”.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Loop,
              parent: m.parent,
              branch: m.branch,
              loop: LoopMode.While,
            ),
          ),
          _Tool(
            'Count items in a list',
            'Store how many items a list has, to use in a condition or a request.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Set,
              parent: m.parent,
              branch: m.branch,
              setOp: SetOp.Count,
            ),
          ),
          _Tool(
            'Add up numbers',
            'Store the total of a number field across a list, e.g. the sum of all prices.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Set,
              parent: m.parent,
              branch: m.branch,
              setOp: SetOp.Sum,
            ),
          ),
          _Tool(
            'Set a variable',
            'Store a value, or the first / last item of a list, for later steps.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Set,
              parent: m.parent,
              branch: m.branch,
              setOp: SetOp.Value,
            ),
          ),
          _Tool(
            'Wait',
            "Pause for a while, e.g. before checking a job's status again.",
            () => state.addWorkflowLogic(
              tb,
              StepKind.Wait,
              parent: m.parent,
              branch: m.branch,
            ),
          ),
          _Tool(
            'Stop',
            'End the loop or the whole workflow, optionally marking it as failed.',
            () => state.addWorkflowLogic(
              tb,
              StepKind.Stop,
              parent: m.parent,
              branch: m.branch,
            ),
          ),
        ];
        body = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              for (final t in tools)
                Clickable(
                  onClick: () => done(t.add),
                  cursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        T(t.title, weight: FontWeight.w600),
                        T(t.hint, color: pal.muted, size: 12),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
    }
    return ModalBox(
      title: 'Add to workflow',
      onClose: () => state.modal = null,
      width: 680,
      height: 560,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        if (mode == 'New request')
          Btn(
            label: 'Create & add',
            onClick: () {
              state.addNewWorkflowStep(
                tb,
                name,
                method,
                url,
                parent: m.parent,
                branch: m.branch,
              );
              state.modal = null;
            },
            primary: true,
            enabled: name.trim().isNotEmpty,
          ),
      ],
      content: [
        Tabs(
          items: const ['Existing request', 'New request', 'Logic'],
          selected: mode,
          onSelect: (v) => setState(() => mode = v),
        ),
        Expanded(child: body),
      ],
    );
  }
}
