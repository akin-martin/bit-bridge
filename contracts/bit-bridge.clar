;; BitBridge: Bitcoin-Backed Lending Protocol
;;
;; A secure and capital-efficient DeFi protocol that enables Bitcoin holders
;; to access USD-denominated liquidity without selling their BTC.
;;
;; Built on Stacks Layer 2, BitBridge creates a trustless bridge between
;; Bitcoin's security and DeFi's flexibility, allowing users to:
;;   - Deposit BTC as collateral
;;   - Borrow USD-pegged stablecoins
;;   - Maintain sovereign ownership of their Bitcoin
;;   - Participate in the DeFi ecosystem while holding BTC
;;

;; Constants

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u1001))
(define-constant ERR_BORROW_LIMIT_EXCEEDED (err u1002))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u1003))
(define-constant ERR_VAULT_ALREADY_EXISTS (err u1004))
(define-constant ERR_VAULT_NOT_FOUND (err u1005))
(define-constant ERR_INSUFFICIENT_DEPOSIT (err u1006))
(define-constant ERR_INSUFFICIENT_REPAYMENT (err u1007))
(define-constant ERR_INVALID_AMOUNT (err u1008))
(define-constant ERR_MINIMUM_COLLATERAL_RATIO (err u1009))
(define-constant ERR_VAULT_NOT_UNDERCOLLATERALIZED (err u1010))
(define-constant ERR_ORACLE_ERROR (err u1011))
(define-constant ERR_PROTOCOL_PAUSED (err u1012))

;; Configuration values

(define-data-var minimum-collateral-ratio uint u150) ;; 150% expressed as percentage
(define-data-var liquidation-threshold uint u125) ;; 125% expressed as percentage 
(define-data-var liquidation-penalty uint u10) ;; 10% expressed as percentage
(define-data-var borrow-interest-rate uint u5) ;; 5% annual interest rate
(define-data-var protocol-fee-rate uint u1) ;; 1% of interest as protocol fee
(define-data-var oracle-price-validity-period uint u3600) ;; 1 hour in seconds
(define-data-var protocol-paused bool false)

;; State variables

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; BTC price in USD (scaled by 10^8)
(define-data-var btc-price-in-usd uint u0)
(define-data-var btc-price-last-updated uint u0)

;; Vault storage
(define-map vaults
    { owner: principal }
    {
        collateral-amount: uint, ;; Satoshis
        borrowed-amount: uint, ;; USD cents
        interest-accumulated: uint, ;; USD cents
        last-interest-update: uint, ;; Block height
    }
)

;; Protocol reserves
(define-map protocol-reserves
    { asset: (string-ascii 10) }
    { amount: uint }
)

;; Protocol statistics
(define-data-var total-collateral uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var total-fees-collected uint u0)

;; Governance token balances
(define-map governance-token-balances
    { owner: principal }
    { balance: uint }
)

;; Authorization checks

(define-private (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-authorized-oracle)
    ;; In a production environment, we would have a whitelist of authorized oracles
    (is-eq tx-sender (var-get contract-owner))
)

(define-private (assert-not-paused)
    (ok (asserts! (not (var-get protocol-paused)) ERR_PROTOCOL_PAUSED))
)

;; Math helper functions

(define-private (mul-div
        (a uint)
        (b uint)
        (c uint)
    )
    (begin
        (asserts! (> c u0) ERR_INVALID_AMOUNT)
        (ok (/ (* a b) c))
    )
)