;; Project Funding Contract
;; Milestone-based funding for documentary projects

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_INVALID_DATA (err u400))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_MILESTONE_NOT_READY (err u403))
(define-constant ERR_PROJECT_NOT_ACTIVE (err u405))
(define-constant ERR_FUNDING_COMPLETE (err u406))
(define-constant ERR_VOTING_ENDED (err u407))
(define-constant ERR_ALREADY_VOTED (err u408))

;; Platform constants
(define-constant PLATFORM_FEE_PERCENTAGE u3) ;; 3%
(define-constant MIN_FUNDING_GOAL u1000) ;; Minimum 1000 microSTX
(define-constant MAX_MILESTONES u10)
(define-constant VOTING_PERIOD u144) ;; ~24 hours in blocks

;; Project status constants
(define-constant STATUS_DRAFT u1)
(define-constant STATUS_ACTIVE u2)
(define-constant STATUS_FUNDED u3)
(define-constant STATUS_IN_PROGRESS u4)
(define-constant STATUS_COMPLETED u5)
(define-constant STATUS_CANCELLED u6)

;; Milestone status constants
(define-constant MILESTONE_PENDING u1)
(define-constant MILESTONE_SUBMITTED u2)
(define-constant MILESTONE_APPROVED u3)
(define-constant MILESTONE_REJECTED u4)
(define-constant MILESTONE_FUNDS_RELEASED u5)

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var next-contribution-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var platform-treasury uint u0)
(define-data-var contract-active bool true)

;; Data Structures

;; Project Information
(define-map projects
  { project-id: uint }
  {
    creator: principal,
    title: (string-ascii 200),
    description: (string-ascii 1000),
    category: (string-ascii 50),
    funding-goal: uint,
    current-funding: uint,
    creation-date: uint,
    funding-deadline: uint,
    status: uint,
    milestones-count: uint,
    contributors-count: uint,
    is-verified: bool,
    metadata-uri: (string-ascii 200),
    social-impact-goals: (list 5 (string-ascii 100))
  }
)

;; Project Milestones
(define-map milestones
  { milestone-id: uint }
  {
    project-id: uint,
    milestone-number: uint,
    title: (string-ascii 200),
    description: (string-ascii 500),
    funding-percentage: uint,
    expected-completion: uint,
    deliverables: (list 5 (string-ascii 100)),
    status: uint,
    submission-date: uint,
    approval-votes: uint,
    rejection-votes: uint,
    evidence-uri: (string-ascii 200),
    funds-released: uint
  }
)

;; Contributions
(define-map contributions
  { contribution-id: uint }
  {
    project-id: uint,
    contributor: principal,
    amount: uint,
    contribution-date: uint,
    reward-tier: uint,
    message: (string-ascii 300),
    is-anonymous: bool,
    refund-requested: bool,
    refund-processed: bool
  }
)

;; Milestone Voting
(define-map milestone-votes
  { milestone-id: uint, voter: principal }
  {
    vote: bool, ;; true for approve, false for reject
    voting-power: uint,
    vote-date: uint,
    justification: (string-ascii 300)
  }
)

;; Creator Profiles
(define-map creators
  { creator: principal }
  {
    name: (string-ascii 100),
    bio: (string-ascii 500),
    portfolio-uri: (string-ascii 200),
    verification-status: (string-ascii 20),
    projects-created: uint,
    total-funds-raised: uint,
    reputation-score: uint,
    social-links: (list 5 (string-ascii 100))
  }
)

;; Contributor Rewards
(define-map rewards
  { project-id: uint, tier: uint }
  {
    min-contribution: uint,
    title: (string-ascii 100),
    description: (string-ascii 300),
    estimated-delivery: uint,
    max-backers: (optional uint),
    current-backers: uint,
    physical-reward: bool
  }
)

;; Project Updates
(define-map project-updates
  { project-id: uint, update-id: uint }
  {
    title: (string-ascii 200),
    content: (string-ascii 1000),
    posted-date: uint,
    author: principal,
    update-type: (string-ascii 50),
    media-uri: (optional (string-ascii 200))
  }
)

;; Lookup Maps
(define-map project-by-creator { creator: principal, project-index: uint } { project-id: uint })
(define-map contributor-projects { contributor: principal, project-id: uint } { total-contributed: uint })

;; Read-only Functions

(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-contribution (contribution-id uint))
  (map-get? contributions { contribution-id: contribution-id })
)

(define-read-only (get-creator-profile (creator principal))
  (map-get? creators { creator: creator })
)

(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM_FEE_PERCENTAGE) u100)
)

(define-read-only (calculate-funding-progress (project-id uint))
  (match (get-project project-id)
    project-data
      (let ((current (get current-funding project-data))
            (goal (get funding-goal project-data)))
        (if (> goal u0)
          (/ (* current u100) goal)
          u0
        )
      )
    u0
  )
)

(define-read-only (is-funding-deadline-passed (project-id uint))
  (match (get-project project-id)
    project-data
      (> block-height (get funding-deadline project-data))
    true
  )
)

(define-read-only (get-milestone-voting-power (milestone-id uint) (voter principal))
  (match (get-milestone milestone-id)
    milestone-data
      (let ((project-id (get project-id milestone-data)))
        (match (map-get? contributor-projects { contributor: voter, project-id: project-id })
          contribution-data (get total-contributed contribution-data)
          u0
        )
      )
    u0
  )
)

(define-read-only (get-next-project-id)
  (var-get next-project-id)
)

(define-read-only (get-platform-treasury)
  (var-get platform-treasury)
)

;; Public Functions

;; Register as creator
(define-public (register-creator
  (name (string-ascii 100))
  (bio (string-ascii 500))
  (portfolio-uri (string-ascii 200))
  (social-links (list 5 (string-ascii 100))))
  
  (let ((existing-creator (map-get? creators { creator: tx-sender })))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-none existing-creator) ERR_ALREADY_EXISTS)
    
    (map-set creators
      { creator: tx-sender }
      {
        name: name,
        bio: bio,
        portfolio-uri: portfolio-uri,
        verification-status: "pending",
        projects-created: u0,
        total-funds-raised: u0,
        reputation-score: u50, ;; Starting reputation
        social-links: social-links
      }
    )
    (ok true)
  )
)

;; Submit project proposal
(define-public (submit-project-proposal
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (category (string-ascii 50))
  (funding-goal uint)
  (funding-deadline uint)
  (metadata-uri (string-ascii 200))
  (social-impact-goals (list 5 (string-ascii 100))))
  
  (let ((project-id (var-get next-project-id)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (>= funding-goal MIN_FUNDING_GOAL) ERR_INVALID_DATA)
    (asserts! (> funding-deadline block-height) ERR_INVALID_DATA)
    (asserts! (is-some (map-get? creators { creator: tx-sender })) ERR_NOT_AUTHORIZED)
    
    (map-set projects
      { project-id: project-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        category: category,
        funding-goal: funding-goal,
        current-funding: u0,
        creation-date: block-height,
        funding-deadline: funding-deadline,
        status: STATUS_DRAFT,
        milestones-count: u0,
        contributors-count: u0,
        is-verified: false,
        metadata-uri: metadata-uri,
        social-impact-goals: social-impact-goals
      }
    )
    
    (var-set next-project-id (+ project-id u1))
    (ok project-id)
  )
)

;; Add milestone to project
(define-public (add-milestone
  (project-id uint)
  (title (string-ascii 200))
  (description (string-ascii 500))
  (funding-percentage uint)
  (expected-completion uint)
  (deliverables (list 5 (string-ascii 100))))
  
  (let (
    (milestone-id (var-get next-milestone-id))
    (project-data (unwrap! (map-get? projects { project-id: project-id }) ERR_NOT_FOUND))
    (current-milestones (get milestones-count project-data))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq tx-sender (get creator project-data)) ERR_NOT_AUTHORIZED)
    (asserts! (< current-milestones MAX_MILESTONES) ERR_INVALID_DATA)
    (asserts! (<= funding-percentage u100) ERR_INVALID_DATA)
    (asserts! (> expected-completion block-height) ERR_INVALID_DATA)
    
    (map-set milestones
      { milestone-id: milestone-id }
      {
        project-id: project-id,
        milestone-number: (+ current-milestones u1),
        title: title,
        description: description,
        funding-percentage: funding-percentage,
        expected-completion: expected-completion,
        deliverables: deliverables,
        status: MILESTONE_PENDING,
        submission-date: u0,
        approval-votes: u0,
        rejection-votes: u0,
        evidence-uri: "",
        funds-released: u0
      }
    )
    
    ;; Update project milestone count
    (map-set projects
      { project-id: project-id }
      (merge project-data { milestones-count: (+ current-milestones u1) })
    )
    
    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)
  )
)

;; Activate project for funding
(define-public (activate-project (project-id uint))
  (let ((project-data (unwrap! (map-get? projects { project-id: project-id }) ERR_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (or 
      (is-eq tx-sender (get creator project-data))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status project-data) STATUS_DRAFT) ERR_INVALID_DATA)
    (asserts! (> (get milestones-count project-data) u0) ERR_INVALID_DATA)
    
    (map-set projects
      { project-id: project-id }
      (merge project-data { status: STATUS_ACTIVE, is-verified: true })
    )
    (ok true)
  )
)

;; Contribute to project
(define-public (contribute-to-project
  (project-id uint)
  (amount uint)
  (reward-tier uint)
  (message (string-ascii 300))
  (is-anonymous bool))
  
  (let (
    (contribution-id (var-get next-contribution-id))
    (project-data (unwrap! (map-get? projects { project-id: project-id }) ERR_NOT_FOUND))
    (platform-fee (calculate-platform-fee amount))
    (net-contribution (- amount platform-fee))
    (new-funding (+ (get current-funding project-data) net-contribution))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status project-data) STATUS_ACTIVE) ERR_PROJECT_NOT_ACTIVE)
    (asserts! (not (is-funding-deadline-passed project-id)) ERR_INVALID_DATA)
    (asserts! (> amount u0) ERR_INVALID_DATA)
    
    ;; Transfer STX from contributor
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Record contribution
    (map-set contributions
      { contribution-id: contribution-id }
      {
        project-id: project-id,
        contributor: tx-sender,
        amount: net-contribution,
        contribution-date: block-height,
        reward-tier: reward-tier,
        message: message,
        is-anonymous: is-anonymous,
        refund-requested: false,
        refund-processed: false
      }
    )
    
    ;; Update project funding
    (map-set projects
      { project-id: project-id }
      (merge project-data {
        current-funding: new-funding,
        contributors-count: (+ (get contributors-count project-data) u1)
      })
    )
    
    ;; Update contributor tracking
    (map-set contributor-projects
      { contributor: tx-sender, project-id: project-id }
      { total-contributed: (+ net-contribution
        (default-to u0 (get total-contributed 
          (map-get? contributor-projects { contributor: tx-sender, project-id: project-id })))
      ) }
    )
    
    ;; Update platform treasury
    (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
    
    ;; Check if funding goal is reached
    (if (>= new-funding (get funding-goal project-data))
      (map-set projects
        { project-id: project-id }
        (merge project-data { 
          current-funding: new-funding,
          status: STATUS_FUNDED,
          contributors-count: (+ (get contributors-count project-data) u1)
        })
      )
      true
    )
    
    (var-set next-contribution-id (+ contribution-id u1))
    (ok contribution-id)
  )
)

;; Submit milestone for review
(define-public (submit-milestone
  (milestone-id uint)
  (evidence-uri (string-ascii 200)))
  
  (let (
    (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
    (project-data (unwrap! (map-get? projects { project-id: (get project-id milestone-data) }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq tx-sender (get creator project-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) MILESTONE_PENDING) ERR_MILESTONE_NOT_READY)
    (asserts! (>= (get status project-data) STATUS_FUNDED) ERR_PROJECT_NOT_ACTIVE)
    
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data {
        status: MILESTONE_SUBMITTED,
        submission-date: block-height,
        evidence-uri: evidence-uri
      })
    )
    (ok true)
  )
)

;; Vote on milestone
(define-public (vote-on-milestone
  (milestone-id uint)
  (approve bool)
  (justification (string-ascii 300)))
  
  (let (
    (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
    (voting-power (get-milestone-voting-power milestone-id tx-sender))
    (existing-vote (map-get? milestone-votes { milestone-id: milestone-id, voter: tx-sender }))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) MILESTONE_SUBMITTED) ERR_MILESTONE_NOT_READY)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (> voting-power u0) ERR_NOT_AUTHORIZED) ;; Must be a contributor
    
    ;; Record vote
    (map-set milestone-votes
      { milestone-id: milestone-id, voter: tx-sender }
      {
        vote: approve,
        voting-power: voting-power,
        vote-date: block-height,
        justification: justification
      }
    )
    
    ;; Update milestone vote counts
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data {
        approval-votes: (if approve 
          (+ (get approval-votes milestone-data) voting-power)
          (get approval-votes milestone-data)
        ),
        rejection-votes: (if approve
          (get rejection-votes milestone-data)
          (+ (get rejection-votes milestone-data) voting-power)
        )
      })
    )
    
    (ok true)
  )
)

;; Release milestone funds
(define-public (release-milestone-funds (milestone-id uint))
  (let (
    (milestone-data (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_NOT_FOUND))
    (project-data (unwrap! (map-get? projects { project-id: (get project-id milestone-data) }) ERR_NOT_FOUND))
    (total-votes (+ (get approval-votes milestone-data) (get rejection-votes milestone-data)))
    (approval-threshold (/ (* total-votes u51) u100)) ;; 51% approval needed
    (funds-to-release (/ (* (get current-funding project-data) (get funding-percentage milestone-data)) u100))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) MILESTONE_SUBMITTED) ERR_MILESTONE_NOT_READY)
    (asserts! (>= (get approval-votes milestone-data) approval-threshold) ERR_NOT_AUTHORIZED)
    (asserts! (> total-votes u0) ERR_INVALID_DATA)
    
    ;; Transfer funds to creator
    (try! (as-contract (stx-transfer? funds-to-release tx-sender (get creator project-data))))
    
    ;; Update milestone status
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone-data {
        status: MILESTONE_FUNDS_RELEASED,
        funds-released: funds-to-release
      })
    )
    
    (ok funds-to-release)
  )
)

;; Admin functions
(define-public (toggle-contract-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active))
  )
)


;; title: project-funding
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

