import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/features/dialogs/cookies_logic.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

const _nameW = 160.0;
const _pathW = 110.0;
const _expiresW = 96.0;
const _flagsW = 196.0;
const _actionsW = 84.0;
const _gap = 10.0;

/// Above this many cookies, clearing them asks for confirmation.
const _confirmClearOver = 5;

/// Lists the cookies kept for this session, grouped by domain.
class CookiesDialog extends StatefulWidget {
  const CookiesDialog({super.key, required this.state});
  final AppState state;

  @override
  State<CookiesDialog> createState() => _CookiesDialogState();
}

class _CookiesDialogState extends State<CookiesDialog> {
  String _query = '';
  final Set<String> _collapsed = {};
  final Set<StoredCookie> _open = {};
  bool _confirmClear = false;

  AppState get state => widget.state;
  CookieJar get _jar => HttpExecutor.cookies;

  void _close() {
    if (_confirmClear) return setState(() => _confirmClear = false);
    state.modal = null;
  }

  void _copy(String text, String what) {
    Platform.copy(text);
    state.showToast('Copied $what');
  }

  void _clearAll() {
    if (_jar.cookies.length > _confirmClearOver && !_confirmClear) {
      setState(() => _confirmClear = true);
      return;
    }
    _jar.removeAll();
    setState(() {
      _confirmClear = false;
      _open.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = List<StoredCookie>.of(_jar.cookies);
    final groups = groupCookies(all, _query);
    final shown = groups.fold<int>(0, (n, g) => n + g.cookies.length);
    final now = DateTime.now();
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBox(
          title: 'Cookies',
          onClose: _close,
          width: 860,
          height: 560,
          actions: [
            Btn(
              label: 'Clear all',
              onClick: _clearAll,
              danger: true,
              enabled: all.isNotEmpty,
            ),
            const Spacer(),
            Btn(label: 'Close', onClick: _close, primary: true),
          ],
          content: [
            _toolbar(p, shown, groups.length),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: all.isEmpty ? _empty(p) : _table(p, groups, now),
              ),
            ),
          ],
        ),
        if (_confirmClear)
          ModalBox(
            title: 'Clear all cookies',
            onClose: _close,
            width: 420,
            actions: [
              Btn(label: 'Cancel', onClick: _close),
              Btn(
                label: 'Clear ${all.length} cookies',
                onClick: _clearAll,
                danger: true,
              ),
            ],
            content: [
              T(
                'Remove all ${all.length} cookies? Servers will have to set them again.',
              ),
            ],
          ),
      ],
    );
  }

  Widget _toolbar(Pal p, int count, int domains) => Row(
    spacing: 10,
    children: [
      Expanded(
        child: Field(
          value: _query,
          onChange: (v) => setState(() => _query = v),
          placeholder: 'Filter by name, value or domain',
          highlightVars: false,
        ),
      ),
      T(cookieCountLabel(count, domains), color: p.muted, size: 12),
    ],
  );

  Widget _empty(Pal p) => Center(
    child: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Ico(Ic.cookie, tint: p.muted, size: 36),
          T('No cookies yet', size: 15, weight: FontWeight.w600),
          T(
            'Cookies set by responses are kept for this session only and are gone when the app closes.',
            color: p.muted,
            size: 12,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _table(Pal p, List<CookieGroup> groups, DateTime now) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            foregroundDecoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              spacing: _gap,
              children: [
                const SizedBox(width: _nameW, child: SectionLabel('NAME')),
                const Expanded(child: SectionLabel('VALUE')),
                const SizedBox(width: _pathW, child: SectionLabel('PATH')),
                const SizedBox(
                  width: _expiresW,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SectionLabel('EXPIRES'),
                  ),
                ),
                const SizedBox(width: _flagsW, child: SectionLabel('FLAGS')),
                const SizedBox(width: _actionsW),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(child: T('No cookies match "$_query"', color: p.muted))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final g in groups) ...[
                          _groupHeader(p, g),
                          if (!_collapsed.contains(g.domain))
                            for (final c in g.cookies) ...[
                              _row(p, c, now),
                              if (_open.contains(c)) _detail(p, c, now),
                            ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(Pal p, CookieGroup g) {
    final open = !_collapsed.contains(g.domain);
    return HoverBuilder(
      onTap: () => setState(
        () => open ? _collapsed.add(g.domain) : _collapsed.remove(g.domain),
      ),
      cursor: SystemMouseCursors.click,
      builder: (ctx, hov) => Container(
        key: ValueKey('group-${g.domain}'),
        height: 34,
        padding: const EdgeInsets.only(left: 8, right: 10),
        color: hov ? p.selected : p.hover,
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          spacing: 6,
          children: [
            Chevron(open: open),
            Flexible(
              child: T(
                g.domain.isEmpty ? '(no domain)' : g.domain,
                mono: true,
                weight: FontWeight.w600,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            T(
              '${g.cookies.length}',
              color: p.muted,
              size: 11,
              weight: FontWeight.w600,
            ),
            const Spacer(),
            if (hov)
              IconBtn(
                key: ValueKey('delete-domain-${g.domain}'),
                icon: Ic.delete,
                color: p.err,
                onClick: () => setState(() {
                  _open.removeAll(g.cookies);
                  _jar.removeDomain(g.domain);
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tag(Pal p, CookieFlag f) {
    final c = switch (f) {
      CookieFlag.secure => p.ok,
      CookieFlag.httpOnly => p.accent,
      CookieFlag.hostOnly => p.muted,
      CookieFlag.session => p.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: T(
        f.label,
        color: c,
        size: 11,
        weight: FontWeight.w600,
        maxLines: 1,
      ),
    );
  }

  Widget _row(Pal p, StoredCookie c, DateTime now) {
    final open = _open.contains(c);
    final expired = c.expires != null && !c.expires!.isAfter(now);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      onTap: () => setState(() => open ? _open.remove(c) : _open.add(c)),
      builder: (ctx, hov) => Container(
        key: ValueKey('cookie-${c.domain}|${c.path}|${c.name}'),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: open
            ? p.selected
            : hov
            ? p.hover
            : const Color(0x00000000),
        foregroundDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          spacing: _gap,
          children: [
            SizedBox(
              width: _nameW,
              child: T(
                c.name,
                mono: true,
                color: p.syntaxKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: T(
                c.value,
                mono: true,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: _pathW,
              child: T(
                c.path ?? '/',
                mono: true,
                color: p.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: _expiresW,
              child: T(
                relativeExpiry(c.expires, now),
                color: expired ? p.err : p.muted,
                size: 12,
                maxLines: 1,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: _flagsW,
              child: ClipRect(
                child: Row(
                  spacing: 4,
                  children: [for (final f in cookieFlags(c)) _tag(p, f)],
                ),
              ),
            ),
            SizedBox(
              width: _actionsW,
              child: hov
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconBtn(
                          key: ValueKey('copy-value-${c.name}'),
                          icon: Ic.copy,
                          onClick: () => _copy(c.value, 'value of ${c.name}'),
                        ),
                        IconBtn(
                          key: ValueKey('copy-pair-${c.name}'),
                          icon: Ic.code,
                          onClick: () => _copy(cookiePair(c), cookiePair(c)),
                        ),
                        IconBtn(
                          key: ValueKey('delete-${c.name}'),
                          icon: Ic.delete,
                          color: p.err,
                          onClick: () => setState(() {
                            _open.remove(c);
                            _jar.removeCookie(c);
                          }),
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(Pal p, StoredCookie c, DateTime now) {
    Widget attr(String k, String v) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        T(k, color: p.muted, size: 12),
        T(v, mono: true, size: 12),
      ],
    );
    final exp = c.expires;
    return Container(
      key: ValueKey('detail-${c.name}'),
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
      color: p.bg.withValues(alpha: 0.5),
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.border.withValues(alpha: 0.5)),
        ),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            const SectionLabel('VALUE'),
            Text(
              c.value.isEmpty ? '(empty)' : c.value,
              style: monoStyle(
                fontSize: 12.5,
                color: p.text,
                height: 1.4,
              ).copyWith(decoration: TextDecoration.none),
            ),
            Wrap(
              spacing: 18,
              runSpacing: 2,
              children: [
                attr('Domain', c.domain ?? ''),
                attr('Path', c.path ?? '/'),
                attr('Expires', exp == null ? 'Session' : cookieDateText(exp)),
                attr('Secure', c.secure ? 'yes' : 'no'),
                attr('HttpOnly', c.isHttpOnly ? 'yes' : 'no'),
                attr('Host only', c.hostOnly ? 'yes' : 'no'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
