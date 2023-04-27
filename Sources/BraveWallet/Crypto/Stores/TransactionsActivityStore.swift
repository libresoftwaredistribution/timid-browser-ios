/* Copyright 2023 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import BraveCore
import SwiftUI

class TransactionsActivityStore: ObservableObject {
  @Published var transactionSummaries: [TransactionSummary] = []
  
  @Published private(set) var currencyCode: String = CurrencyCode.usd.code {
    didSet {
      currencyFormatter.currencyCode = currencyCode
      guard oldValue != currencyCode else { return }
      update()
    }
  }
  
  let currencyFormatter: NumberFormatter = .usdCurrencyFormatter
  
  private var solEstimatedTxFeesCache: [String: UInt64] = [:]
  private var assetPricesCache: [String: Double] = [:]
  
  private let keyringService: BraveWalletKeyringService
  private let rpcService: BraveWalletJsonRpcService
  private let walletService: BraveWalletBraveWalletService
  private let assetRatioService: BraveWalletAssetRatioService
  private let blockchainRegistry: BraveWalletBlockchainRegistry
  private let txService: BraveWalletTxService
  private let solTxManagerProxy: BraveWalletSolanaTxManagerProxy
  
  init(
    keyringService: BraveWalletKeyringService,
    rpcService: BraveWalletJsonRpcService,
    walletService: BraveWalletBraveWalletService,
    assetRatioService: BraveWalletAssetRatioService,
    blockchainRegistry: BraveWalletBlockchainRegistry,
    txService: BraveWalletTxService,
    solTxManagerProxy: BraveWalletSolanaTxManagerProxy
  ) {
    self.keyringService = keyringService
    self.rpcService = rpcService
    self.walletService = walletService
    self.assetRatioService = assetRatioService
    self.blockchainRegistry = blockchainRegistry
    self.txService = txService
    self.solTxManagerProxy = solTxManagerProxy
    
    keyringService.add(self)
    txService.add(self)

    Task { @MainActor in
      self.currencyCode = await walletService.defaultBaseCurrency()
    }
  }
  
  private var updateTask: Task<Void, Never>?
  func update() {
    updateTask?.cancel()
    updateTask = Task { @MainActor in
      let allKeyrings = await keyringService.keyrings(
        for: WalletConstants.supportedCoinTypes
      )
      let allAccountInfos = allKeyrings.flatMap(\.accountInfos)
      // Only transactions for the selected network
      // for each coin type are returned
      var selectedNetworkForCoin: [BraveWallet.CoinType: BraveWallet.NetworkInfo] = [:]
      for coin in WalletConstants.supportedCoinTypes {
        selectedNetworkForCoin[coin] = await rpcService.network(coin)
      }
      let allTransactions = await txService.allTransactions(
        for: allKeyrings
      ).filter { $0.txStatus != .rejected }
      let userVisibleTokens = await walletService.allVisibleUserAssets(
        in: Array(selectedNetworkForCoin.values)
      ).flatMap(\.tokens)
      let allTokens = await blockchainRegistry.allTokens(
        in: Array(selectedNetworkForCoin.values)
      ).flatMap(\.tokens)
      guard !Task.isCancelled else { return }
      // display transactions prior to network request to fetch
      // estimated solana tx fees & asset prices
      self.transactionSummaries = self.transactionSummaries(
        transactions: allTransactions,
        selectedNetworkForCoin: selectedNetworkForCoin,
        accountInfos: allAccountInfos,
        userVisibleTokens: userVisibleTokens,
        allTokens: allTokens,
        assetRatios: assetPricesCache,
        solEstimatedTxFees: solEstimatedTxFeesCache
      )
      guard !self.transactionSummaries.isEmpty else { return }
      
      if allTransactions.contains(where: { $0.coin == .sol }) {
        let solTransactionIds = allTransactions.filter { $0.coin == .sol }.map(\.id)
        await updateSolEstimatedTxFeesCache(solTransactionIds: solTransactionIds)
      }
      
      let allVisibleTokenAssetRatioIds = userVisibleTokens.map(\.assetRatioId)
      await updateAssetPricesCache(assetRatioIds: allVisibleTokenAssetRatioIds)
      
      guard !Task.isCancelled else { return }
      self.transactionSummaries = self.transactionSummaries(
        transactions: allTransactions,
        selectedNetworkForCoin: selectedNetworkForCoin,
        accountInfos: allAccountInfos,
        userVisibleTokens: userVisibleTokens,
        allTokens: allTokens,
        assetRatios: assetPricesCache,
        solEstimatedTxFees: solEstimatedTxFeesCache
      )
    }
  }
  
  private func transactionSummaries(
    transactions: [BraveWallet.TransactionInfo],
    selectedNetworkForCoin: [BraveWallet.CoinType: BraveWallet.NetworkInfo],
    accountInfos: [BraveWallet.AccountInfo],
    userVisibleTokens: [BraveWallet.BlockchainToken],
    allTokens: [BraveWallet.BlockchainToken],
    assetRatios: [String: Double],
    solEstimatedTxFees: [String: UInt64]
  ) -> [TransactionSummary] {
    transactions.compactMap { transaction in
      guard let network = selectedNetworkForCoin[transaction.coin] else {
        return nil
      }
      return TransactionParser.transactionSummary(
        from: transaction,
        network: network,
        accountInfos: accountInfos,
        visibleTokens: userVisibleTokens,
        allTokens: allTokens,
        assetRatios: assetRatios,
        solEstimatedTxFee: solEstimatedTxFees[transaction.id],
        currencyFormatter: currencyFormatter
      )
    }.sorted(by: { $0.createdTime > $1.createdTime })
  }
  
  @MainActor private func updateSolEstimatedTxFeesCache(solTransactionIds: [String]) async {
    let fees = await solTxManagerProxy.estimatedTxFees(for: solTransactionIds)
    for (key, value) in fees { // update cached values
      self.solEstimatedTxFeesCache[key] = value
    }
  }
  
  @MainActor private func updateAssetPricesCache(assetRatioIds: [String]) async {
    let prices = await assetRatioService.fetchPrices(
      for: assetRatioIds,
      toAssets: [currencyFormatter.currencyCode],
      timeframe: .oneDay
    ).compactMapValues { Double($0) }
    for (key, value) in prices { // update cached values
      self.assetPricesCache[key] = value
    }
  }
  
  func transactionDetailsStore(
    for transaction: BraveWallet.TransactionInfo
  ) -> TransactionDetailsStore {
    TransactionDetailsStore(
      transaction: transaction,
      keyringService: keyringService,
      walletService: walletService,
      rpcService: rpcService,
      assetRatioService: assetRatioService,
      blockchainRegistry: blockchainRegistry,
      solanaTxManagerProxy: solTxManagerProxy
    )
  }
}

extension TransactionsActivityStore: BraveWalletKeyringServiceObserver {
  func keyringCreated(_ keyringId: String) { }
  
  func keyringRestored(_ keyringId: String) { }
  
  func keyringReset() { }
  
  func locked() { }
  
  func unlocked() { }
  
  func backedUp() { }
  
  func accountsChanged() {
    update()
  }
  
  func accountsAdded(_ coin: BraveWallet.CoinType, addresses: [String]) {
    update()
  }
  
  func autoLockMinutesChanged() { }
  
  func selectedAccountChanged(_ coin: BraveWallet.CoinType) { }
}

extension TransactionsActivityStore: BraveWalletTxServiceObserver {
  func onNewUnapprovedTx(_ txInfo: BraveWallet.TransactionInfo) {
    update()
  }
  
  func onUnapprovedTxUpdated(_ txInfo: BraveWallet.TransactionInfo) {
    update()
  }
  
  func onTransactionStatusChanged(_ txInfo: BraveWallet.TransactionInfo) {
    update()
  }
  
  func onTxServiceReset() {
    update()
  }
}