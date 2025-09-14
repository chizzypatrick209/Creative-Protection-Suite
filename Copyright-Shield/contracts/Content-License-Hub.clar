;; Content Protection Platform Smart Contract
;; A comprehensive smart contract for protecting digital content with licensing and royalty management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-LICENSE-TYPE (err u106))
(define-constant ERR-CONTENT-NOT-ACTIVE (err u107))
(define-constant ERR-LICENSE-EXPIRED (err u108))
(define-constant ERR-INVALID-DISPUTE-STATUS (err u109))
(define-constant ERR-INVALID-PERCENTAGE (err u110))
(define-constant ERR-INVALID-DURATION (err u111))
(define-constant ERR-TRANSFER-FAILED (err u112))
(define-constant ERR-INVALID-INPUT (err u113))

;; Data Variables
(define-data-var next-content-id uint u1)
(define-data-var next-license-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% in basis points
(define-data-var min-license-duration uint u86400) ;; 1 day in blocks
(define-data-var max-license-duration uint u52560) ;; ~1 year in blocks (144 blocks/day)

;; Data Maps
(define-map content-registry
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 256),
    description: (string-utf8 1024),
    content-hash: (string-ascii 64),
    license-price: uint,
    royalty-percentage: uint, ;; in basis points (1% = 100)
    is-active: bool,
    created-at: uint,
    total-licenses: uint,
    total-revenue: uint
  }
)

(define-map content-licenses
  { license-id: uint }
  {
    content-id: uint,
    licensee: principal,
    license-type: (string-ascii 32), ;; "commercial", "personal", "educational"
    start-time: uint,
    end-time: uint,
    amount-paid: uint,
    is-active: bool
  }
)

(define-map user-profiles
  { user: principal }
  {
    display-name: (string-utf8 64),
    email-hash: (string-ascii 64),
    is-verified: bool,
    content-count: uint,
    total-earnings: uint,
    reputation-score: uint
  }
)

(define-map content-disputes
  { dispute-id: uint }
  {
    content-id: uint,
    complainant: principal,
    respondent: principal,
    dispute-type: (string-ascii 32), ;; "copyright", "plagiarism", "misuse"
    description: (string-utf8 512),
    status: (string-ascii 16), ;; "open", "investigating", "resolved", "dismissed"
    created-at: uint,
    resolved-at: (optional uint),
    resolver: (optional principal)
  }
)

(define-map royalty-splits
  { content-id: uint, recipient: principal }
  { percentage: uint } ;; in basis points
)

(define-map platform-moderators
  { moderator: principal }
  { is-active: bool, added-at: uint }
)

;; User license tracking map for efficient lookup
(define-map user-content-licenses
  { user: principal, content-id: uint }
  { license-id: uint, end-time: uint }
)

;; Read-only functions
(define-read-only (get-content-info (content-id uint))
  (map-get? content-registry { content-id: content-id })
)

(define-read-only (get-license-info (license-id uint))
  (map-get? content-licenses { license-id: license-id })
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-dispute-info (dispute-id uint))
  (map-get? content-disputes { dispute-id: dispute-id })
)

(define-read-only (get-royalty-split (content-id uint) (recipient principal))
  (map-get? royalty-splits { content-id: content-id, recipient: recipient })
)

(define-read-only (is-content-licensed-by-user (content-id uint) (user principal))
  (let ((current-time stacks-block-height))
    (match (map-get? user-content-licenses { user: user, content-id: content-id })
      user-license
      (let ((license-id (get license-id user-license)))
        (match (get-license-info license-id)
          license-data
          (and 
            (get is-active license-data)
            (<= (get start-time license-data) current-time)
            (>= (get end-time license-data) current-time))
          false))
      false)))

(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

(define-read-only (calculate-license-fee (content-id uint) (license-type (string-ascii 32)))
  (match (get-content-info content-id)
    content
    (let ((base-price (get license-price content)))
      (if (is-eq license-type "commercial")
        (ok (* base-price u2)) ;; 2x for commercial
        (if (is-eq license-type "educational") 
          (ok (/ base-price u2)) ;; 0.5x for educational
          (if (is-eq license-type "personal")
            (ok base-price) ;; 1x for personal
            ERR-INVALID-LICENSE-TYPE))))
    ERR-NOT-FOUND))

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)

;; Private functions
(define-private (is-valid-moderator (moderator principal))
  (match (map-get? platform-moderators { moderator: moderator })
    moderator-data (get is-active moderator-data)
    false))

(define-private (validate-license-type (license-type (string-ascii 32)))
  (or (is-eq license-type "commercial") 
      (is-eq license-type "personal") 
      (is-eq license-type "educational")))

(define-private (validate-dispute-type (dispute-type (string-ascii 32)))
  (or (is-eq dispute-type "copyright") 
      (is-eq dispute-type "plagiarism") 
      (is-eq dispute-type "misuse")))

(define-private (validate-resolution-status (resolution (string-ascii 16)))
  (or (is-eq resolution "resolved") 
      (is-eq resolution "dismissed")))

(define-private (distribute-royalties (content-id uint) (total-amount uint))
  (match (get-content-info content-id)
    content
    (let ((creator (get creator content))
          (platform-fee (/ (* total-amount (var-get platform-fee-percentage)) u10000))
          (creator-amount (- total-amount platform-fee)))
      ;; Ensure creator-amount is valid
      (asserts! (>= total-amount platform-fee) ERR-INVALID-AMOUNT)
      ;; Transfer platform fee to contract owner
      (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))
      ;; Transfer remaining amount to creator
      (try! (stx-transfer? creator-amount tx-sender creator))
      (ok true))
    ERR-NOT-FOUND))

(define-private (update-user-earnings (user principal) (amount uint))
  (match (get-user-profile user)
    profile
    (map-set user-profiles
      { user: user }
      (merge profile { total-earnings: (+ (get total-earnings profile) amount) }))
    ;; If profile doesn't exist, create basic one
    (map-set user-profiles
      { user: user }
      {
        display-name: u"Default User",
        email-hash: "default-hash",
        is-verified: false,
        content-count: u0,
        total-earnings: amount,
        reputation-score: u100
      })))

;; Public functions

;; User Management
(define-public (create-user-profile (display-name (string-utf8 64)) (email-hash (string-ascii 64)))
  (let ((user tx-sender))
    (asserts! (is-none (get-user-profile user)) ERR-ALREADY-EXISTS)
    (asserts! (> (len display-name) u0) ERR-INVALID-INPUT)
    (map-set user-profiles
      { user: user }
      {
        display-name: display-name,
        email-hash: email-hash,
        is-verified: false,
        content-count: u0,
        total-earnings: u0,
        reputation-score: u100
      })
    (ok true)))

(define-public (update-user-profile (display-name (string-utf8 64)) (email-hash (string-ascii 64)))
  (let ((user tx-sender))
    (match (get-user-profile user)
      profile 
      (begin
        (asserts! (> (len display-name) u0) ERR-INVALID-INPUT)
        (map-set user-profiles
          { user: user }
          (merge profile { display-name: display-name, email-hash: email-hash }))
        (ok true))
      ERR-NOT-FOUND)))

;; Content Management
(define-public (register-content 
    (title (string-ascii 256)) 
    (description (string-utf8 1024)) 
    (content-hash (string-ascii 64))
    (license-price uint)
    (royalty-percentage uint))
  (let ((content-id (var-get next-content-id))
        (creator tx-sender)
        (current-time stacks-block-height))
    (asserts! (<= royalty-percentage u10000) ERR-INVALID-PERCENTAGE) ;; Max 100%
    (asserts! (> license-price u0) ERR-INVALID-AMOUNT)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len content-hash) u0) ERR-INVALID-INPUT)
    
    ;; Register content
    (map-set content-registry
      { content-id: content-id }
      {
        creator: creator,
        title: title,
        description: description,
        content-hash: content-hash,
        license-price: license-price,
        royalty-percentage: royalty-percentage,
        is-active: true,
        created-at: current-time,
        total-licenses: u0,
        total-revenue: u0
      })
    
    ;; Update user profile
    (match (get-user-profile creator)
      profile 
      (map-set user-profiles
        { user: creator }
        (merge profile { content-count: (+ (get content-count profile) u1) }))
      (map-set user-profiles
        { user: creator }
        {
          display-name: u"Default User",
          email-hash: "default-hash",
          is-verified: false,
          content-count: u1,
          total-earnings: u0,
          reputation-score: u100
        }))
    
    ;; Increment content ID counter
    (var-set next-content-id (+ content-id u1))
    (ok content-id)))

(define-public (update-content-status (content-id uint) (is-active bool))
  (match (get-content-info content-id)
    content
    (begin
      (asserts! (is-eq (get creator content) tx-sender) ERR-UNAUTHORIZED-ACCESS)
      (map-set content-registry
        { content-id: content-id }
        (merge content { is-active: is-active }))
      (ok true))
    ERR-NOT-FOUND))

(define-public (update-license-price (content-id uint) (new-price uint))
  (match (get-content-info content-id)
    content
    (begin
      (asserts! (is-eq (get creator content) tx-sender) ERR-UNAUTHORIZED-ACCESS)
      (asserts! (> new-price u0) ERR-INVALID-AMOUNT)
      (map-set content-registry
        { content-id: content-id }
        (merge content { license-price: new-price }))
      (ok true))
    ERR-NOT-FOUND))

;; License Management
(define-public (purchase-license 
    (content-id uint) 
    (license-type (string-ascii 32))
    (duration uint))
  (let ((content (unwrap! (get-content-info content-id) ERR-NOT-FOUND))
        (license-id (var-get next-license-id))
        (current-time stacks-block-height)
        (license-fee (unwrap! (calculate-license-fee content-id license-type) ERR-INVALID-LICENSE-TYPE)))
    
    (asserts! (get is-active content) ERR-CONTENT-NOT-ACTIVE)
    (asserts! (>= duration (var-get min-license-duration)) ERR-INVALID-DURATION)
    (asserts! (<= duration (var-get max-license-duration)) ERR-INVALID-DURATION)
    (asserts! (validate-license-type license-type) ERR-INVALID-LICENSE-TYPE)
    (asserts! (not (is-eq (get creator content) tx-sender)) ERR-UNAUTHORIZED-ACCESS) ;; Creator can't buy own license
    
    ;; Create license
    (map-set content-licenses
      { license-id: license-id }
      {
        content-id: content-id,
        licensee: tx-sender,
        license-type: license-type,
        start-time: current-time,
        end-time: (+ current-time duration),
        amount-paid: license-fee,
        is-active: true
      })
    
    ;; Update user-content-licenses mapping for efficient lookup
    (map-set user-content-licenses
      { user: tx-sender, content-id: content-id }
      { license-id: license-id, end-time: (+ current-time duration) })
    
    ;; Update content stats
    (map-set content-registry
      { content-id: content-id }
      (merge content {
        total-licenses: (+ (get total-licenses content) u1),
        total-revenue: (+ (get total-revenue content) license-fee)
      }))
    
    ;; Distribute royalties
    (try! (distribute-royalties content-id license-fee))
    
    ;; Update creator earnings
    (update-user-earnings (get creator content) license-fee)
    
    ;; Increment license ID counter
    (var-set next-license-id (+ license-id u1))
    (ok license-id)))

(define-public (revoke-license (license-id uint))
  (match (get-license-info license-id)
    license
    (let ((content (unwrap! (get-content-info (get content-id license)) ERR-NOT-FOUND)))
      (asserts! (or (is-eq (get creator content) tx-sender) 
                    (is-eq (get licensee license) tx-sender)) ERR-UNAUTHORIZED-ACCESS)
      (map-set content-licenses
        { license-id: license-id }
        (merge license { is-active: false }))
      (ok true))
    ERR-NOT-FOUND))

;; Dispute Management
(define-public (file-dispute 
    (content-id uint) 
    (respondent principal)
    (dispute-type (string-ascii 32))
    (description (string-utf8 512)))
  (let ((dispute-id (var-get next-dispute-id))
        (current-time stacks-block-height))
    (asserts! (is-some (get-content-info content-id)) ERR-NOT-FOUND)
    (asserts! (validate-dispute-type dispute-type) ERR-INVALID-DISPUTE-STATUS)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender respondent)) ERR-INVALID-INPUT) ;; Can't dispute against yourself
    
    (map-set content-disputes
      { dispute-id: dispute-id }
      {
        content-id: content-id,
        complainant: tx-sender,
        respondent: respondent,
        dispute-type: dispute-type,
        description: description,
        status: "open",
        created-at: current-time,
        resolved-at: none,
        resolver: none
      })
    
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)))

(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 16)))
  (match (get-dispute-info dispute-id)
    dispute
    (let ((current-time stacks-block-height))
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-valid-moderator tx-sender)) ERR-UNAUTHORIZED-ACCESS)
      (asserts! (is-eq (get status dispute) "open") ERR-INVALID-DISPUTE-STATUS)
      (asserts! (validate-resolution-status resolution) ERR-INVALID-DISPUTE-STATUS)
      
      (map-set content-disputes
        { dispute-id: dispute-id }
        (merge dispute {
          status: resolution,
          resolved-at: (some current-time),
          resolver: (some tx-sender)
        }))
      (ok true))
    ERR-NOT-FOUND))

;; Royalty Management
(define-public (add-royalty-split (content-id uint) (recipient principal) (percentage uint))
  (match (get-content-info content-id)
    content
    (begin
      (asserts! (is-eq (get creator content) tx-sender) ERR-UNAUTHORIZED-ACCESS)
      (asserts! (<= percentage u10000) ERR-INVALID-PERCENTAGE) ;; Max 100%
      (asserts! (> percentage u0) ERR-INVALID-PERCENTAGE) ;; Must be > 0%
      
      (map-set royalty-splits
        { content-id: content-id, recipient: recipient }
        { percentage: percentage })
      (ok true))
    ERR-NOT-FOUND))

(define-public (remove-royalty-split (content-id uint) (recipient principal))
  (match (get-content-info content-id)
    content
    (begin
      (asserts! (is-eq (get creator content) tx-sender) ERR-UNAUTHORIZED-ACCESS)
      (map-delete royalty-splits { content-id: content-id, recipient: recipient })
      (ok true))
    ERR-NOT-FOUND))

;; Admin functions
(define-public (add-moderator (moderator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (is-eq moderator CONTRACT-OWNER)) ERR-INVALID-INPUT) ;; Owner is already a moderator
    (map-set platform-moderators
      { moderator: moderator }
      { is-active: true, added-at: stacks-block-height })
    (ok true)))

(define-public (remove-moderator (moderator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (match (map-get? platform-moderators { moderator: moderator })
      moderator-data
      (begin
        (map-set platform-moderators
          { moderator: moderator }
          (merge moderator-data { is-active: false }))
        (ok true))
      ERR-NOT-FOUND)))

(define-public (update-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-fee-percentage u1000) ERR-INVALID-PERCENTAGE) ;; Max 10%
    (var-set platform-fee-percentage new-fee-percentage)
    (ok true)))

(define-public (verify-user (user principal))
  (begin
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-valid-moderator tx-sender)) ERR-UNAUTHORIZED-ACCESS)
    (match (get-user-profile user)
      profile
      (begin
        (map-set user-profiles
          { user: user }
          (merge profile { is-verified: true }))
        (ok true))
      ERR-NOT-FOUND)))

(define-public (update-license-duration-limits (min-duration uint) (max-duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (< min-duration max-duration) ERR-INVALID-DURATION)
    (asserts! (> min-duration u0) ERR-INVALID-DURATION)
    (var-set min-license-duration min-duration)
    (var-set max-license-duration max-duration)
    (ok true)))