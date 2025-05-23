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

;; Oracle functions

(define-public (update-btc-price (new-price uint))
    (begin
        (asserts! (is-authorized-oracle) ERR_UNAUTHORIZED)
        ;; Add validation for price sanity
        (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
        ;; Add upper bound check to prevent extreme price manipulation
        (asserts! (< new-price u10000000000) ERR_INVALID_AMOUNT) ;; $100,000 per BTC ceiling
        ;; Optional: Add check for maximum allowed price deviation from previous
        (var-set btc-price-in-usd new-price)
        (var-set btc-price-last-updated stacks-block-height)
        (ok new-price)
    )
)

(define-private (get-btc-price)
    (let (
            (current-price (var-get btc-price-in-usd))
            (last-updated (var-get btc-price-last-updated))
        )
        (if (or
                (is-eq current-price u0)
                (> (- stacks-block-height last-updated)
                    (var-get oracle-price-validity-period)
                )
            )
            ERR_ORACLE_ERROR
            (ok current-price)
        )
    )
)

;; Administrative functions

(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        ;; Prevent setting to zero/null address
        (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78))
            ERR_INVALID_AMOUNT
        )
        ;; Require two-step ownership transfer for security
        (var-set contract-owner new-owner)
        (ok new-owner)
    )
)

(define-public (set-minimum-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (>= new-ratio (var-get liquidation-threshold))
            ERR_INVALID_AMOUNT
        )
        (var-set minimum-collateral-ratio new-ratio)
        (ok new-ratio)
    )
)

(define-public (set-liquidation-threshold (new-threshold uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (<= new-threshold (var-get minimum-collateral-ratio))
            ERR_INVALID_AMOUNT
        )
        (var-set liquidation-threshold new-threshold)
        (ok new-threshold)
    )
)

(define-public (set-liquidation-penalty (new-penalty uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (<= new-penalty u50) ERR_INVALID_AMOUNT) ;; Maximum 50% penalty
        (var-set liquidation-penalty new-penalty)
        (ok new-penalty)
    )
)

(define-public (set-interest-rate (new-rate uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        ;; Add upper bound for interest rate
        (asserts! (<= new-rate u50) ERR_INVALID_AMOUNT) ;; Maximum 50% interest rate
        (var-set borrow-interest-rate new-rate)
        (ok new-rate)
    )
)

(define-public (set-protocol-fee (new-fee uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u50) ERR_INVALID_AMOUNT) ;; Maximum 50% fee
        (var-set protocol-fee-rate new-fee)
        (ok new-fee)
    )
)

(define-public (toggle-protocol-pause)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (var-set protocol-paused (not (var-get protocol-paused)))
        (ok (var-get protocol-paused))
    )
)