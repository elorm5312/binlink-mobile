import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/design_system/household_design_system.dart';

class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.height, this.width = double.infinity, this.radius = 20, this.dark = false});

  final double height;
  final double width;
  final double radius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: dark ? const Color(0xFF263241) : const Color(0xFFE7E2DA),
      highlightColor: dark ? const Color(0xFF344252) : const Color(0xFFFAFAF9),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: HouseholdColors.card,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.itemHeight = 86, this.dark = false});

  final int count;
  final double itemHeight;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Skeleton(height: itemHeight, dark: dark),
        ),
      ),
    );
  }
}
