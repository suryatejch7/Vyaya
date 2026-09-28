import 'package:flutter/material.dart';
import 'dart:ui';
import '../models/quick_action_item.dart';

class GlassBottomSheet extends StatefulWidget {
  final List<QuickActionItem> items;

  const GlassBottomSheet({super.key, required this.items});

  @override
  State<GlassBottomSheet> createState() => _GlassBottomSheetState();
}

class _GlassBottomSheetState extends State<GlassBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate height to fit all items without scrolling
    final itemHeight = 72.0;
    final spacing = 8.0;
    final baseHeight = 90.0; // handle bar + title + padding
    final contentHeight =
        baseHeight + (widget.items.length * (itemHeight + spacing)) + 12;
    final maxHeight = screenHeight * 0.6;
    final finalHeight = contentHeight.clamp(200.0, maxHeight);

    return GestureDetector(
      // Tap anywhere outside the bottom sheet to dismiss
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        height: double.infinity,
        child: GestureDetector(
          // Prevent tap on the sheet itself from dismissing
          onTap: () {},
          child: SlideTransition(
            position: _slideAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                // Only 8 dp side margins so the sheet fully covers the nav
                // bar and the + / filter button (16 dp from each edge).
                margin: const EdgeInsets.fromLTRB(8, 20, 8, 20),
                width: screenWidth - 16,
                height: finalHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle bar
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 18), // Increased from 16
                          // Title
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Action items - scrollable when they overflow
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: widget.items.map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SizedBox(
                                      height: itemHeight,
                                      child: _buildActionItem(item),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(QuickActionItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: item.onTap,
        child: Container(
          height: 64.0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 45, // Slightly smaller
                height: 45, // Slightly smaller
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                  size: 22, // Slightly smaller
                ),
              ),
              const SizedBox(width: 14), // Reduced spacing
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min, // Important: prevent overflow
                  children: [
                    Flexible(
                      // Wrap title in Flexible
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 15, // Slightly smaller
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2), // Reduced spacing
                    Flexible(
                      // Wrap subtitle in Flexible
                      child: Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 13, // Slightly smaller
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.5),
                size: 14, // Slightly smaller
              ),
            ],
          ),
        ),
      ),
    );
  }
}
