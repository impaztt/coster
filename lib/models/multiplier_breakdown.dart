/// Diagnostic snapshot of the tap/dps multiplier stacks. Built by
/// GameNotifier.multiplierBreakdown for the dev debug sheet so we can
/// see exactly which layer is contributing what.
///
/// After §3.1 v1, layers carry an [additive] flag. Additive layers
/// contribute (value − 1) to a shared bonus pool that's combined as
/// `(1 + Σbonus)`, then multiplied with the multiplicative layers.
class MultiplierLayer {
  final String name;
  final double tap;
  final double dps;

  /// When true, this layer's contribution is (value − 1) added to the
  /// additive pool. When false, the layer multiplies the stack directly.
  final bool additive;

  const MultiplierLayer({
    required this.name,
    required this.tap,
    required this.dps,
    this.additive = false,
  });
}

class MultiplierBreakdown {
  /// Base tap power before any layer.
  final double tapBase;

  /// Base 초당 수익 sum (producer dps before any layer).
  final double dpsBase;

  /// Each layer in the stack, in display order.
  final List<MultiplierLayer> layers;

  /// Final tap power, matches GameNotifier._calcTapPower().
  final double tapTotal;

  /// Final 초당 수익, matches GameNotifier._calcDps().
  final double dpsTotal;

  /// Product of every non-additive layer's tap value.
  final double multiplicativeTap;
  final double multiplicativeDps;

  /// Σ(value − 1) across additive layers — the additive bonus pool.
  /// Combined as `(1 + this)` and multiplied with the multiplicative stack.
  final double additiveTapFraction;
  final double additiveDpsFraction;

  const MultiplierBreakdown({
    required this.tapBase,
    required this.dpsBase,
    required this.layers,
    required this.tapTotal,
    required this.dpsTotal,
    required this.multiplicativeTap,
    required this.multiplicativeDps,
    required this.additiveTapFraction,
    required this.additiveDpsFraction,
  });

  double get totalTapMult => tapBase > 0 ? tapTotal / tapBase : 0;
  double get totalDpsMult => dpsBase > 0 ? dpsTotal / dpsBase : 0;
}
