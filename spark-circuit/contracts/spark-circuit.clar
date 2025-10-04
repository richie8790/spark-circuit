;; Spark Circuit - Zero-Knowledge Identity Verification System
;; A decentralized credential verification and reputation management platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-proof (err u104))
(define-constant err-authority-not-trusted (err u105))

;; Data Variables
(define-data-var reputation-token-name (string-ascii 32) "Spark Reputation Token")
(define-data-var reputation-token-symbol (string-ascii 10) "SPARK")
(define-data-var total-reputation-supply uint u0)

;; Data Maps

;; Trusted Certification Authorities Registry
(define-map trusted-authorities
    principal
    {
        name: (string-ascii 100),
        active: bool,
        credentials-issued: uint,
        trust-score: uint
    }
)

;; Credential Circuits Registry
;; Stores cryptographic circuit identifiers for credentials
(define-map credential-circuits
    {holder: principal, circuit-id: (buff 32)}
    {
        authority: principal,
        circuit-hash: (buff 32),
        verification-key: (buff 64),
        issued-at: uint,
        expires-at: uint,
        credential-type: (string-ascii 50),
        verified: bool
    }
)

;; Verification Proofs
;; Stores zero-knowledge proofs for credential verification
(define-map verification-proofs
    {holder: principal, proof-id: (buff 32)}
    {
        circuit-id: (buff 32),
        proof-hash: (buff 32),
        verified-at: uint,
        verifier: principal
    }
)

;; Reputation Balances
(define-map reputation-balances
    principal
    uint
)

;; Reputation Scores
(define-map reputation-scores
    principal
    {
        total-score: uint,
        verified-engagements: uint,
        credentials-count: uint,
        last-updated: uint
    }
)

;; Work Engagement Verifications
(define-map work-engagements
    {holder: principal, engagement-id: (buff 32)}
    {
        verifier: principal,
        reputation-earned: uint,
        verified-at: uint,
        engagement-type: (string-ascii 50)
    }
)

;; Read-only functions

;; Check if an authority is trusted
(define-read-only (is-trusted-authority (authority principal))
    (match (map-get? trusted-authorities authority)
        authority-data (get active authority-data)
        false
    )
)

;; Get authority information
(define-read-only (get-authority-info (authority principal))
    (map-get? trusted-authorities authority)
)

;; Get credential circuit information
(define-read-only (get-credential-circuit (holder principal) (circuit-id (buff 32)))
    (map-get? credential-circuits {holder: holder, circuit-id: circuit-id})
)

;; Get verification proof
(define-read-only (get-verification-proof (holder principal) (proof-id (buff 32)))
    (map-get? verification-proofs {holder: holder, proof-id: proof-id})
)

;; Get reputation balance
(define-read-only (get-reputation-balance (account principal))
    (default-to u0 (map-get? reputation-balances account))
)

;; Get reputation score
(define-read-only (get-reputation-score (account principal))
    (map-get? reputation-scores account)
)

;; Get work engagement
(define-read-only (get-work-engagement (holder principal) (engagement-id (buff 32)))
    (map-get? work-engagements {holder: holder, engagement-id: engagement-id})
)

;; Get total reputation supply
(define-read-only (get-total-reputation-supply)
    (var-get total-reputation-supply)
)

;; Public functions

;; Register a trusted certification authority
(define-public (register-authority (authority principal) (name (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? trusted-authorities authority)) err-already-exists)
        (ok (map-set trusted-authorities
            authority
            {
                name: name,
                active: true,
                credentials-issued: u0,
                trust-score: u100
            }
        ))
    )
)

;; Deactivate a certification authority
(define-public (deactivate-authority (authority principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (match (map-get? trusted-authorities authority)
            authority-data
            (ok (map-set trusted-authorities
                authority
                (merge authority-data {active: false})
            ))
            err-not-found
        )
    )
)

;; Issue a credential circuit
(define-public (issue-credential-circuit 
    (holder principal)
    (circuit-id (buff 32))
    (circuit-hash (buff 32))
    (verification-key (buff 64))
    (expires-at uint)
    (credential-type (string-ascii 50))
)
    (let
        (
            (authority tx-sender)
        )
        (asserts! (is-trusted-authority authority) err-authority-not-trusted)
        (asserts! (is-none (map-get? credential-circuits {holder: holder, circuit-id: circuit-id})) err-already-exists)
        
        ;; Create credential circuit
        (map-set credential-circuits
            {holder: holder, circuit-id: circuit-id}
            {
                authority: authority,
                circuit-hash: circuit-hash,
                verification-key: verification-key,
                issued-at: block-height,
                expires-at: expires-at,
                credential-type: credential-type,
                verified: false
            }
        )
        
        ;; Update authority stats
        (match (map-get? trusted-authorities authority)
            authority-data
            (map-set trusted-authorities
                authority
                (merge authority-data {credentials-issued: (+ (get credentials-issued authority-data) u1)})
            )
            false
        )
        
        ;; Update holder's reputation score
        (update-credential-count holder)
        
        (ok true)
    )
)

;; Submit verification proof
(define-public (submit-verification-proof
    (circuit-id (buff 32))
    (proof-id (buff 32))
    (proof-hash (buff 32))
)
    (let
        (
            (holder tx-sender)
        )
        (match (map-get? credential-circuits {holder: holder, circuit-id: circuit-id})
            circuit-data
            (begin
                ;; Store verification proof
                (map-set verification-proofs
                    {holder: holder, proof-id: proof-id}
                    {
                        circuit-id: circuit-id,
                        proof-hash: proof-hash,
                        verified-at: block-height,
                        verifier: contract-owner
                    }
                )
                
                ;; Mark credential as verified
                (map-set credential-circuits
                    {holder: holder, circuit-id: circuit-id}
                    (merge circuit-data {verified: true})
                )
                
                (ok true)
            )
            err-not-found
        )
    )
)

;; Verify work engagement and mint reputation tokens
(define-public (verify-work-engagement
    (holder principal)
    (engagement-id (buff 32))
    (reputation-amount uint)
    (engagement-type (string-ascii 50))
)
    (let
        (
            (verifier tx-sender)
        )
        (asserts! (is-none (map-get? work-engagements {holder: holder, engagement-id: engagement-id})) err-already-exists)
        
        ;; Record work engagement
        (map-set work-engagements
            {holder: holder, engagement-id: engagement-id}
            {
                verifier: verifier,
                reputation-earned: reputation-amount,
                verified-at: block-height,
                engagement-type: engagement-type
            }
        )
        
        ;; Mint reputation tokens
        (mint-reputation holder reputation-amount)
        
        ;; Update reputation score
        (update-engagement-score holder reputation-amount)
        
        (ok true)
    )
)

;; Transfer reputation tokens
(define-public (transfer-reputation (amount uint) (sender principal) (recipient principal))
    (let
        (
            (sender-balance (get-reputation-balance sender))
        )
        (asserts! (is-eq tx-sender sender) err-unauthorized)
        (asserts! (>= sender-balance amount) err-not-found)
        
        (map-set reputation-balances sender (- sender-balance amount))
        (map-set reputation-balances recipient (+ (get-reputation-balance recipient) amount))
        
        (ok true)
    )
)

;; Private functions

;; Mint reputation tokens
(define-private (mint-reputation (recipient principal) (amount uint))
    (begin
        (map-set reputation-balances 
            recipient 
            (+ (get-reputation-balance recipient) amount)
        )
        (var-set total-reputation-supply (+ (var-get total-reputation-supply) amount))
        true
    )
)

;; Update credential count in reputation score
(define-private (update-credential-count (holder principal))
    (match (map-get? reputation-scores holder)
        score-data
        (map-set reputation-scores
            holder
            (merge score-data {
                credentials-count: (+ (get credentials-count score-data) u1),
                last-updated: block-height
            })
        )
        (map-set reputation-scores
            holder
            {
                total-score: u0,
                verified-engagements: u0,
                credentials-count: u1,
                last-updated: block-height
            }
        )
    )
)

;; Update engagement score
(define-private (update-engagement-score (holder principal) (reputation-amount uint))
    (match (map-get? reputation-scores holder)
        score-data
        (map-set reputation-scores
            holder
            (merge score-data {
                total-score: (+ (get total-score score-data) reputation-amount),
                verified-engagements: (+ (get verified-engagements score-data) u1),
                last-updated: block-height
            })
        )
        (map-set reputation-scores
            holder
            {
                total-score: reputation-amount,
                verified-engagements: u1,
                credentials-count: u0,
                last-updated: block-height
            }
        )
    )
)

;; Initialize contract
(begin
    (map-set reputation-scores
        contract-owner
        {
            total-score: u0,
            verified-engagements: u0,
            credentials-count: u0,
            last-updated: block-height
        }
    )
)
