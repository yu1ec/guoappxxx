import 'package:flutter/material.dart';

import 'models.dart';

enum _SourceTier { green, restricted }

/// 绿色 / 限制级站源切换弹窗，点击站点立即切换并关闭。
Future<void> showSourceSwitchDialog(
  BuildContext context, {
  required List<SourceSite> sources,
  required SourceSite current,
  required bool allSources,
  required void Function(SourceSite source, {required bool allSources}) onSelected,
  bool showRestricted = false,
}) {
  final theme = Theme.of(context);
  final green = sources.where((s) => !SourceSite.isRestricted(s.id)).toList();
  final restricted = sources.where((s) => SourceSite.isRestricted(s.id)).toList();
  final restrictedCount = restricted.length;

  String currentLabel;
  if (allSources && green.length > 1) {
    currentLabel = '全部站源';
  } else {
    currentLabel = current.entryName == current.name
        ? current.name
        : '${current.groupName} · ${current.entryName}';
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var tier = _SourceTier.green;
      if (green.isEmpty && restricted.isNotEmpty && showRestricted) {
        tier = _SourceTier.restricted;
      }

      void pick(SourceSite source, {required bool aggregate}) {
        Navigator.pop(dialogContext);
        onSelected(source, allSources: aggregate);
      }

      return StatefulBuilder(
        builder: (context, setState) {
          final tierSources = tier == _SourceTier.green ? green : restricted;
          final showAllTile =
              tier == _SourceTier.green && green.length > 1;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '切换站源',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '当前：$currentLabel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '分类仅筛选列表，点击站源立即切换',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (showRestricted && restricted.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (green.isNotEmpty)
                            ChoiceChip(
                              label: Text('绿色 ${green.length}'),
                              selected: tier == _SourceTier.green,
                              onSelected: (_) =>
                                  setState(() => tier = _SourceTier.green),
                            ),
                          ChoiceChip(
                            label: Text('限制级 $restrictedCount'),
                            selected: tier == _SourceTier.restricted,
                            onSelected: (_) =>
                                setState(() => tier = _SourceTier.restricted),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const columns = 4;
                            const spacing = 8.0;
                            final cellWidth =
                                (constraints.maxWidth - spacing * (columns - 1)) /
                                columns;
                            final cells = <Widget>[];
                            if (showAllTile) {
                              final selected = allSources;
                              cells.add(
                                _SourceCell(
                                  width: cellWidth,
                                  label: '全部站源',
                                  selected: selected,
                                  onTap: () =>
                                      pick(green.first, aggregate: true),
                                ),
                              );
                            }
                            for (final site in tierSources) {
                              final label = site.entryName == site.name
                                  ? site.name
                                  : site.entryName;
                              final selected =
                                  !allSources && site.id == current.id;
                              final cfBadge = site.id == 'cloudfront' ||
                                  site.id == 'cg51';
                              cells.add(
                                _SourceCell(
                                  width: cellWidth,
                                  label: label,
                                  selected: selected,
                                  cfBadge: cfBadge,
                                  onTap: () =>
                                      pick(site, aggregate: false),
                                ),
                              );
                            }
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: cells,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _SourceCell extends StatelessWidget {
  const _SourceCell({
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
    this.cfBadge = false,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool cfBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    final fill = selected
        ? scheme.primary.withValues(alpha: 0.08)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final textColor = selected ? scheme.primary : scheme.onSurface;

    return SizedBox(
      width: width,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                    height: 1.15,
                  ),
                ),
                if (cfBadge)
                  Positioned(
                    left: 2,
                    top: -6,
                    child: Text(
                      'CF',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}