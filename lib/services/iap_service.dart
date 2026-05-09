import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/iap_config.dart';

/// Wraps the in_app_purchase plugin into a simpler façade. The provider
/// listens to [purchaseStream] for grant + acknowledge bookkeeping;
/// dialogs ask for [products] to render store-driven prices.
///
/// This is a *client-side* implementation — we acknowledge on success and
/// trust the local grant. Server-side receipt validation is the upgrade
/// path once the game has servers handling state of record.
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool _loading = false;
  Map<String, ProductDetails> _products = const {};
  final _purchaseCtrl = StreamController<PurchaseDetails>.broadcast();

  bool get available => _available;
  Map<String, ProductDetails> get products => _products;
  Stream<PurchaseDetails> get purchaseStream => _purchaseCtrl.stream;

  Future<void> initialize() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('[IapService] store not available on this device');
      return;
    }
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) =>
          debugPrint('[IapService] purchase stream error: $e'),
    );
    await refreshProducts();
    // Restore non-consumable purchases (ad removal, starter, first-purchase)
    // so users who reinstall don't lose their entitlements.
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[IapService] restore failed: $e');
    }
  }

  Future<void> refreshProducts() async {
    if (!_available || _loading) return;
    _loading = true;
    try {
      final response =
          await _iap.queryProductDetails(IapConfig.allProductIds);
      _products = {
        for (final p in response.productDetails) p.id: p,
      };
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            '[IapService] product IDs not found in store: ${response.notFoundIDs}. '
            'Register them in Google Play Console / App Store Connect.');
      }
    } catch (e) {
      debugPrint('[IapService] queryProductDetails failed: $e');
    } finally {
      _loading = false;
    }
  }

  /// Display the store's purchase sheet. Returns true if the request was
  /// accepted by the platform (NOT whether the purchase ultimately
  /// succeeded — listen on [purchaseStream] for that).
  Future<bool> buy(String productId, {bool consumable = true}) async {
    if (!_available) return false;
    final product = _products[productId];
    if (product == null) {
      debugPrint('[IapService] no ProductDetails for $productId — '
          'is it registered in the store?');
      return false;
    }
    final param = PurchaseParam(productDetails: product);
    try {
      if (consumable) {
        return await _iap.buyConsumable(purchaseParam: param);
      }
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('[IapService] buy failed: $e');
      return false;
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      _purchaseCtrl.add(p);
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (e) {
          debugPrint('[IapService] completePurchase failed: $e');
        }
      }
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _purchaseCtrl.close();
  }
}

/// Map a Google Play product ID to the consumable/non-consumable flag the
/// IAP plugin needs. Non-consumables (ad removal, first-purchase, starter
/// pack) survive restore; everything else is one-shot.
bool iapIsConsumable(String productId) {
  switch (productId) {
    case IapConfig.adRemoval:
    case IapConfig.starterPackage:
    case IapConfig.firstPurchase:
      return false;
    default:
      return true;
  }
}
