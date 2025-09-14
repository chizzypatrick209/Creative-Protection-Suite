;; Content Protection Platform
;; A comprehensive smart contract for protecting digital content with licensing and royalty management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-license-type (err u106))
(define-constant err-content-not-active (err u107))
(define-constant err-license-expired (err u108))
(define-constant err-invalid-dispute-status (err u109))
(define-constant err-invalid-percentage (err u110))

;; Data Variables
(define-data-var next-content-id uint u1)
(define-data-var next-license-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% in basis points
(define-data-var min-license-duration uint u86400) ;; 1 day in seconds
(define-data-var max-license-duration uint u31536000) ;; 1 year in seconds

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
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    (fold check-valid-license 
          (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) ;; Check last 10 licenses (simplified)
          { content-id: content-id, user: user, current-time: current-time, found: false })))

(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

(define-read-only (calculate-license-fee (content-id uint) (license-type (string-ascii 32)))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (let ((base-price (get license-price content)))
      (if (is-eq license-type "commercial")
        (ok (* base-price u2)) ;; 2x for commercial
        (if (is-eq license-type "educational") 
          (ok (/ base-price u2)) ;; 0.5x for educational
          (ok base-price)) ;; 1x for personal
      ))))

;; Private functions
(define-private (check-valid-license (license-check uint) (data { content-id: uint, user: principal, current-time: uint, found: bool }))
  (if (get found data)
    data
    (let ((license-id (+ (get license-check data) (var-get next-license-id))))
      (match (get-license-info license-id)
        license-data 
        (if (and 
              (is-eq (get content-id license-data) (get content-id data))
              (is-eq (get licensee license-data) (get user data))
              (get is-active license-data)
              (<= (get start-time license-data) (get current-time data))
              (>= (get end-time license-data) (get current-time data)))
          (merge data { found: true })
          data)
        data))))

(define-private (is-valid-moderator (moderator principal))
  (match (map-get? platform-moderators { moderator: moderator })
    moderator-data (get is-active moderator-data)
    false))

(define-private (distribute-royalties (content-id uint) (total-amount uint))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (let ((creator (get creator content))
          (platform-fee (/ (* total-amount (var-get platform-fee-percentage)) u10000))
          (creator-amount (- total-amount platform-fee)))
      ;; Transfer platform fee to contract owner
      (try! (stx-transfer? platform-fee tx-sender contract-owner))
      ;; Transfer remaining amount to creator
      (try! (stx-transfer? creator-amount tx-sender creator))
      (ok true))))

;; Public functions

;; User Management
(define-public (create-user-profile (display-name (string-utf8 64)) (email-hash (string-ascii 64)))
  (let ((user tx-sender))
    (asserts! (is-none (get-user-profile user)) (err err-already-exists))
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
        (map-set user-profiles
          { user: user }
          (merge profile { display-name: display-name, email-hash: email-hash }))
        (ok true))
      (err err-not-found))))

;; Content Management
(define-public (register-content 
    (title (string-ascii 256)) 
    (description (string-utf8 1024)) 
    (content-hash (string-ascii 64))
    (license-price uint)
    (royalty-percentage uint))
  (let ((content-id (var-get next-content-id))
        (creator tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    (asserts! (<= royalty-percentage u10000) (err err-invalid-percentage)) ;; Max 100%
    (asserts! (> license-price u0) (err err-invalid-amount))
    
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
          display-name: u"",
          email-hash: u"",
          is-verified: false,
          content-count: u1,
          total-earnings: u0,
          reputation-score: u100
        }))
    
    ;; Increment content ID counter
    (var-set next-content-id (+ content-id u1))
    (ok content-id)))

(define-public (update-content-status (content-id uint) (is-active bool))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (asserts! (is-eq (get creator content) tx-sender) (err err-unauthorized))
    (map-set content-registry
      { content-id: content-id }
      (merge content { is-active: is-active }))
    (ok true)))

(define-public (update-license-price (content-id uint) (new-price uint))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (asserts! (is-eq (get creator content) tx-sender) (err err-unauthorized))
    (asserts! (> new-price u0) (err err-invalid-amount))
    (map-set content-registry
      { content-id: content-id }
      (merge content { license-price: new-price }))
    (ok true)))

;; License Management
(define-public (purchase-license 
    (content-id uint) 
    (license-type (string-ascii 32))
    (duration uint))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found)))
        (license-id (var-get next-license-id))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (license-fee (unwrap! (calculate-license-fee content-id license-type) (err err-invalid-license-type))))
    
    (asserts! (get is-active content) (err err-content-not-active))
    (asserts! (>= duration (var-get min-license-duration)) (err err-invalid-amount))
    (asserts! (<= duration (var-get max-license-duration)) (err err-invalid-amount))
    (asserts! (or (is-eq license-type "commercial") 
                  (is-eq license-type "personal") 
                  (is-eq license-type "educational")) (err err-invalid-license-type))
    
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
    (let ((creator (get creator content)))
      (match (get-user-profile creator)
        profile
        (map-set user-profiles
          { user: creator }
          (merge profile { total-earnings: (+ (get total-earnings profile) license-fee) }))
        true))
    
    ;; Increment license ID counter
    (var-set next-license-id (+ license-id u1))
    (ok license-id)))

(define-public (revoke-license (license-id uint))
  (let ((license (unwrap! (get-license-info license-id) (err err-not-found)))
        (content (unwrap! (get-content-info (get content-id license)) (err err-not-found))))
    (asserts! (or (is-eq (get creator content) tx-sender) 
                  (is-eq (get licensee license) tx-sender)) (err err-unauthorized))
    (map-set content-licenses
      { license-id: license-id }
      (merge license { is-active: false }))
    (ok true)))

;; Dispute Management
(define-public (file-dispute 
    (content-id uint) 
    (respondent principal)
    (dispute-type (string-ascii 32))
    (description (string-utf8 512)))
  (let ((dispute-id (var-get next-dispute-id))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    (asserts! (is-some (get-content-info content-id)) (err err-not-found))
    (asserts! (or (is-eq dispute-type "copyright") 
                  (is-eq dispute-type "plagiarism") 
                  (is-eq dispute-type "misuse")) (err err-invalid-dispute-status))
    
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
  (let ((dispute (unwrap! (get-dispute-info dispute-id) (err err-not-found)))
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    (asserts! (or (is-eq tx-sender contract-owner) (is-valid-moderator tx-sender)) (err err-unauthorized))
    (asserts! (is-eq (get status dispute) "open") (err err-invalid-dispute-status))
    (asserts! (or (is-eq resolution "resolved") (is-eq resolution "dismissed")) (err err-invalid-dispute-status))
    
    (map-set content-disputes
      { dispute-id: dispute-id }
      (merge dispute {
        status: resolution,
        resolved-at: (some current-time),
        resolver: (some tx-sender)
      }))
    (ok true)))

;; Royalty Management
(define-public (add-royalty-split (content-id uint) (recipient principal) (percentage uint))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (asserts! (is-eq (get creator content) tx-sender) (err err-unauthorized))
    (asserts! (<= percentage u10000) (err err-invalid-percentage)) ;; Max 100%
    
    (map-set royalty-splits
      { content-id: content-id, recipient: recipient }
      { percentage: percentage })
    (ok true)))

(define-public (remove-royalty-split (content-id uint) (recipient principal))
  (let ((content (unwrap! (get-content-info content-id) (err err-not-found))))
    (asserts! (is-eq (get creator content) tx-sender) (err err-unauthorized))
    (map-delete royalty-splits { content-id: content-id, recipient: recipient })
    (ok true)))

;; Admin functions
(define-public (add-moderator (moderator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (map-set platform-moderators
      { moderator: moderator }
      { is-active: true, added-at: (unwrap-panic (get-block-info? time (- block-height u1))) })
    (ok true)))

(define-public (remove-moderator (moderator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (match (map-get? platform-moderators { moderator: moderator })
      moderator-data
      (begin
        (map-set platform-moderators
          { moderator: moderator }
          (merge moderator-data { is-active: false }))
        (ok true))
      (err err-not-found))))

(define-public (update-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (<= new-fee-percentage u1000) (err err-invalid-percentage)) ;; Max 10%
    (var-set platform-fee-percentage new-fee-percentage)
    (ok true)))

(define-public (verify-user (user principal))
  (begin
    (asserts! (or (is-eq tx-sender contract-owner) (is-valid-moderator tx-sender)) (err err-unauthorized))
    (match (get-user-profile user)
      profile
      (begin
        (map-set user-profiles
          { user: user }
          (merge profile { is-verified: true }))
        (ok true))
      (err err-not-found))))

(define-public (update-license-duration-limits (min-duration uint) (max-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (< min-duration max-duration) (err err-invalid-amount))
    (var-set min-license-duration min-duration)
    (var-set max-license-duration max-duration)
    (ok true)))