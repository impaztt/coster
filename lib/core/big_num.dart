import 'dart:math' as math;

/// Big number for idle-game magnitudes. Stored as `m * 10^e` with `m` normalized
/// to `[1, 10)` (or `0` for zero). Use it instead of `double` for gold/DPS/
/// stats that can exceed ~1e300 over long play, where double precision drifts.
///
/// Cost expressions (`baseCost * r^lv`) stay on `double` — they fit comfortably
/// within double range for realistic progression and are easier to work with.
class BigNum implements Comparable<BigNum> {
  final double m;
  final int e;

  const BigNum._raw(this.m, this.e);

  const BigNum.zero() : m = 0, e = 0;
  const BigNum.one() : m = 1, e = 0;

  factory BigNum(double mantissa, int exponent) {
    if (mantissa == 0 || mantissa.isNaN || !mantissa.isFinite) {
      return const BigNum.zero();
    }
    var mv = mantissa.abs();
    var ev = exponent;
    while (mv >= 10) {
      mv *= 0.1;
      ev++;
    }
    while (mv < 1) {
      mv *= 10;
      ev--;
    }
    return BigNum._raw(mantissa.isNegative ? -mv : mv, ev);
  }

  factory BigNum.fromDouble(double v) {
    if (v == 0 || v.isNaN || !v.isFinite) return const BigNum.zero();
    final e = (math.log(v.abs()) / math.ln10).floor();
    final m = v / math.pow(10, e).toDouble();
    return BigNum(m, e);
  }

  factory BigNum.fromInt(int v) => BigNum.fromDouble(v.toDouble());

  double toDouble() {
    if (isZero) return 0;
    if (e > 308) return m.isNegative ? double.negativeInfinity : double.infinity;
    if (e < -308) return 0;
    return m * math.pow(10, e).toDouble();
  }

  bool get isZero => m == 0;
  bool get isNegative => m < 0;

  BigNum negate() => BigNum._raw(-m, e);

  BigNum operator +(BigNum other) {
    if (other.isZero) return this;
    if (isZero) return other;
    final diff = e - other.e;
    // Beyond 17 orders of magnitude difference, smaller operand contributes
    // nothing to double precision result.
    if (diff > 17) return this;
    if (diff < -17) return other;
    if (diff >= 0) {
      return BigNum(m + other.m * math.pow(10, -diff).toDouble(), e);
    }
    return BigNum(other.m + m * math.pow(10, diff).toDouble(), other.e);
  }

  BigNum operator -(BigNum other) => this + other.negate();

  BigNum operator *(BigNum other) {
    if (isZero || other.isZero) return const BigNum.zero();
    return BigNum(m * other.m, e + other.e);
  }

  BigNum operator /(BigNum other) {
    if (isZero) return const BigNum.zero();
    if (other.isZero) return const BigNum.zero();
    return BigNum(m / other.m, e - other.e);
  }

  BigNum times(double k) {
    if (k == 0 || isZero || k.isNaN || !k.isFinite) return const BigNum.zero();
    return BigNum(m * k, e);
  }

  BigNum dividedBy(double k) {
    if (isZero || k == 0 || k.isNaN || !k.isFinite) return const BigNum.zero();
    return BigNum(m / k, e);
  }

  BigNum pow(int n) {
    if (n == 0) return const BigNum.one();
    if (n < 0) return const BigNum.one() / pow(-n);
    BigNum result = const BigNum.one();
    BigNum base = this;
    int exp = n;
    while (exp > 0) {
      if (exp & 1 == 1) result = result * base;
      base = base * base;
      exp >>= 1;
    }
    return result;
  }

  @override
  int compareTo(BigNum other) {
    if (isZero && other.isZero) return 0;
    if (isZero) return other.isNegative ? 1 : -1;
    if (other.isZero) return isNegative ? -1 : 1;
    if (isNegative != other.isNegative) return isNegative ? -1 : 1;
    final expCmp = e.compareTo(other.e);
    if (expCmp != 0) return isNegative ? -expCmp : expCmp;
    return m.compareTo(other.m);
  }

  bool operator >(BigNum other) => compareTo(other) > 0;
  bool operator <(BigNum other) => compareTo(other) < 0;
  bool operator >=(BigNum other) => compareTo(other) >= 0;
  bool operator <=(BigNum other) => compareTo(other) <= 0;

  Map<String, dynamic> toJson() => {'m': m, 'e': e};

  factory BigNum.fromJson(Map<String, dynamic> j) => BigNum._raw(
        (j['m'] as num?)?.toDouble() ?? 0,
        j['e'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is BigNum && m == other.m && e == other.e;

  @override
  int get hashCode => Object.hash(m, e);

  @override
  String toString() => isZero ? '0' : '${m}e$e';
}
