(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-invalid-milestone (err u104))
(define-constant err-unauthorized (err u105))

(define-data-var min-stake-amount uint u1000)
(define-data-var platform-fee-percent uint u2)

(define-map Students
    principal
    {
        name: (string-ascii 50),
        course: (string-ascii 100),
        total-milestones: uint,
        completed-milestones: uint,
        total-funding: uint,
        funds-released: uint,
    }
)

(define-map Scholarships
    uint
    {
        donor: principal,
        student: principal,
        amount: uint,
        milestones: uint,
        active: bool,
    }
)

(define-map Mentors
    principal
    {
        name: (string-ascii 50),
        verified: bool,
        students: (list 10 principal),
    }
)

(define-data-var scholarship-counter uint u0)

(define-map ScholarshipActivity
    uint
    {
        last-activity: uint,
        emergency-request: (optional uint),
        emergency-approved: bool,
    }
)

(define-public (register-student
        (name (string-ascii 50))
        (course (string-ascii 100))
        (total-milestones uint)
    )
    (let ((student-data (map-get? Students tx-sender)))
        (asserts! (is-none student-data) err-already-registered)
        (map-set Students tx-sender {
            name: name,
            course: course,
            total-milestones: total-milestones,
            completed-milestones: u0,
            total-funding: u0,
            funds-released: u0,
        })
        (ok true)
    )
)

(define-public (create-scholarship
        (student principal)
        (amount uint)
        (milestones uint)
    )
    (let (
            (student-data (map-get? Students student))
            (scholarship-id (+ (var-get scholarship-counter) u1))
        )
        (asserts! (>= amount (var-get min-stake-amount)) err-insufficient-funds)
        (asserts! (is-some student-data) err-not-registered)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set scholarship-counter scholarship-id)
        (map-set Scholarships scholarship-id {
            donor: tx-sender,
            student: student,
            amount: amount,
            milestones: milestones,
            active: true,
        })
        (map-set ScholarshipActivity scholarship-id {
            last-activity: burn-block-height,
            emergency-request: none,
            emergency-approved: false,
        })
        (ok scholarship-id)
    )
)

(define-public (register-mentor (name (string-ascii 50)))
    (let ((mentor-data (map-get? Mentors tx-sender)))
        (asserts! (is-none mentor-data) err-already-registered)
        (map-set Mentors tx-sender {
            name: name,
            verified: false,
            students: (list),
        })
        (ok true)
    )
)

(define-public (verify-mentor (mentor principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set Mentors mentor
            (merge (unwrap! (map-get? Mentors mentor) err-not-registered) { verified: true })
        )
        (ok true)
    )
)

(define-public (complete-milestone
        (student principal)
        (scholarship-id uint)
    )
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
            (scholarship (unwrap! (map-get? Scholarships scholarship-id) err-not-registered))
            (student-data (unwrap! (map-get? Students student) err-not-registered))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (asserts! (get active scholarship) err-invalid-milestone)
        (asserts!
            (< (get completed-milestones student-data)
                (get total-milestones student-data)
            )
            err-invalid-milestone
        )
        (let (
                (milestone-amount (/ (get amount scholarship) (get milestones scholarship)))
                (platform-fee (/ (* milestone-amount (var-get platform-fee-percent)) u100))
                (student-amount (- milestone-amount platform-fee))
            )
            (try! (as-contract (stx-transfer? student-amount (as-contract tx-sender) student)))
            (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) contract-owner)))
            (map-set Students student
                (merge student-data {
                    completed-milestones: (+ (get completed-milestones student-data) u1),
                    funds-released: (+ (get funds-released student-data) student-amount),
                })
            )
            (let ((activity (default-to {
                    last-activity: u0,
                    emergency-request: none,
                    emergency-approved: false,
                }
                    (map-get? ScholarshipActivity scholarship-id)
                )))
                (map-set ScholarshipActivity scholarship-id
                    (merge activity { last-activity: burn-block-height })
                )
            )
            (ok true)
        )
    )
)

(define-read-only (get-student-info (student principal))
    (ok (map-get? Students student))
)

(define-read-only (get-scholarship-info (scholarship-id uint))
    (ok (map-get? Scholarships scholarship-id))
)

(define-read-only (get-mentor-info (mentor principal))
    (ok (map-get? Mentors mentor))
)

(define-public (update-min-stake-amount (new-amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set min-stake-amount new-amount)
        (ok true)
    )
)

(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u100) (err u106))
        (var-set platform-fee-percent new-fee)
        (ok true)
    )
)

(define-constant err-submission-not-found (err u107))
(define-constant err-already-submitted (err u108))
(define-constant err-already-reviewed (err u109))

(define-map MilestoneSubmissions
    {
        student: principal,
        scholarship-id: uint,
        milestone-number: uint,
    }
    {
        proof-url: (string-ascii 200),
        submission-time: uint,
        status: (string-ascii 20),
        reviewer: (optional principal),
        review-time: (optional uint),
        review-notes: (optional (string-ascii 500)),
    }
)

(define-public (submit-milestone-proof
        (scholarship-id uint)
        (milestone-number uint)
        (proof-url (string-ascii 200))
    )
    (let (
            (student-data (unwrap! (map-get? Students tx-sender) err-not-registered))
            (scholarship (unwrap! (map-get? Scholarships scholarship-id) err-not-registered))
            (submission-key {
                student: tx-sender,
                scholarship-id: scholarship-id,
                milestone-number: milestone-number,
            })
        )
        (asserts! (is-eq tx-sender (get student scholarship)) err-unauthorized)
        (asserts! (is-none (map-get? MilestoneSubmissions submission-key))
            err-already-submitted
        )
        (asserts! (< milestone-number (get total-milestones student-data))
            err-invalid-milestone
        )
        (map-set MilestoneSubmissions submission-key {
            proof-url: proof-url,
            submission-time: burn-block-height,
            status: "pending",
            reviewer: none,
            review-time: none,
            review-notes: none,
        })
        (ok true)
    )
)

(define-public (review-milestone-submission
        (student principal)
        (scholarship-id uint)
        (milestone-number uint)
        (approved bool)
        (review-notes (string-ascii 500))
    )
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
            (submission-key {
                student: student,
                scholarship-id: scholarship-id,
                milestone-number: milestone-number,
            })
            (submission (unwrap! (map-get? MilestoneSubmissions submission-key)
                err-submission-not-found
            ))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (asserts! (is-eq (get status submission) "pending") err-already-reviewed)
        (map-set MilestoneSubmissions submission-key
            (merge submission {
                status: (if approved
                    "approved"
                    "rejected"
                ),
                reviewer: (some tx-sender),
                review-time: (some burn-block-height),
                review-notes: (some review-notes),
            })
        )
        (if approved
            (complete-milestone student scholarship-id)
            (ok true)
        )
    )
)

(define-read-only (get-milestone-submission
        (student principal)
        (scholarship-id uint)
        (milestone-number uint)
    )
    (ok (map-get? MilestoneSubmissions {
        student: student,
        scholarship-id: scholarship-id,
        milestone-number: milestone-number,
    }))
)

(define-constant err-request-not-found (err u110))
(define-constant err-bid-not-found (err u111))
(define-constant err-request-closed (err u112))
(define-constant err-invalid-bid (err u113))
(define-constant err-scholarship-not-inactive (err u114))
(define-constant err-emergency-cooldown (err u115))
(define-constant err-no-emergency-pending (err u116))
(define-constant err-pool-not-found (err u117))
(define-constant err-pool-closed (err u118))
(define-constant err-pool-not-expired (err u119))
(define-constant err-target-not-met (err u120))
(define-constant err-already-contributed (err u121))

(define-data-var scholarship-request-counter uint u0)
(define-data-var bid-counter uint u0)
(define-data-var inactivity-threshold uint u1000)
(define-data-var pool-counter uint u0)

(define-map ScholarshipPools
    uint
    {
        creator: principal,
        student: principal,
        target-amount: uint,
        current-amount: uint,
        deadline: uint,
        milestones: uint,
        status: (string-ascii 20),
        created-at: uint,
    }
)

(define-map PoolContributions
    {
        pool-id: uint,
        contributor: principal,
    }
    {
        amount: uint,
        timestamp: uint,
    }
)

(define-map ScholarshipRequests
    uint
    {
        student: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        requested-amount: uint,
        duration-blocks: uint,
        status: (string-ascii 20),
        created-at: uint,
        selected-bid: (optional uint),
    }
)

(define-map ScholarshipBids
    uint
    {
        request-id: uint,
        donor: principal,
        offered-amount: uint,
        milestones: uint,
        terms: (string-ascii 300),
        created-at: uint,
        status: (string-ascii 20),
    }
)

(define-public (create-scholarship-request
        (title (string-ascii 100))
        (description (string-ascii 500))
        (requested-amount uint)
        (duration-blocks uint)
    )
    (let (
            (student-data (unwrap! (map-get? Students tx-sender) err-not-registered))
            (request-id (+ (var-get scholarship-request-counter) u1))
        )
        (var-set scholarship-request-counter request-id)
        (map-set ScholarshipRequests request-id {
            student: tx-sender,
            title: title,
            description: description,
            requested-amount: requested-amount,
            duration-blocks: duration-blocks,
            status: "open",
            created-at: burn-block-height,
            selected-bid: none,
        })
        (ok request-id)
    )
)

(define-public (place-scholarship-bid
        (request-id uint)
        (offered-amount uint)
        (milestones uint)
        (terms (string-ascii 300))
    )
    (let (
            (request (unwrap! (map-get? ScholarshipRequests request-id)
                err-request-not-found
            ))
            (bid-id (+ (var-get bid-counter) u1))
        )
        (asserts! (is-eq (get status request) "open") err-request-closed)
        (asserts! (>= offered-amount (var-get min-stake-amount)) err-invalid-bid)
        (asserts!
            (< burn-block-height
                (+ (get created-at request) (get duration-blocks request))
            )
            err-request-closed
        )
        (var-set bid-counter bid-id)
        (map-set ScholarshipBids bid-id {
            request-id: request-id,
            donor: tx-sender,
            offered-amount: offered-amount,
            milestones: milestones,
            terms: terms,
            created-at: burn-block-height,
            status: "pending",
        })
        (ok bid-id)
    )
)

(define-public (accept-scholarship-bid (bid-id uint))
    (let (
            (bid (unwrap! (map-get? ScholarshipBids bid-id) err-bid-not-found))
            (request (unwrap! (map-get? ScholarshipRequests (get request-id bid))
                err-request-not-found
            ))
        )
        (asserts! (is-eq tx-sender (get student request)) err-unauthorized)
        (asserts! (is-eq (get status request) "open") err-request-closed)
        (asserts! (is-eq (get status bid) "pending") err-invalid-bid)
        (try! (stx-transfer? (get offered-amount bid) (get donor bid)
            (as-contract tx-sender)
        ))
        (map-set ScholarshipRequests (get request-id bid)
            (merge request {
                status: "funded",
                selected-bid: (some bid-id),
            })
        )
        (map-set ScholarshipBids bid-id (merge bid { status: "accepted" }))
        (let ((scholarship-id (+ (var-get scholarship-counter) u1)))
            (var-set scholarship-counter scholarship-id)
            (map-set Scholarships scholarship-id {
                donor: (get donor bid),
                student: tx-sender,
                amount: (get offered-amount bid),
                milestones: (get milestones bid),
                active: true,
            })
            (map-set ScholarshipActivity scholarship-id {
                last-activity: burn-block-height,
                emergency-request: none,
                emergency-approved: false,
            })
            (ok scholarship-id)
        )
    )
)

(define-read-only (get-scholarship-request (request-id uint))
    (ok (map-get? ScholarshipRequests request-id))
)

(define-read-only (get-scholarship-bid (bid-id uint))
    (ok (map-get? ScholarshipBids bid-id))
)

(define-public (close-scholarship-request (request-id uint))
    (let ((request (unwrap! (map-get? ScholarshipRequests request-id) err-request-not-found)))
        (asserts! (is-eq tx-sender (get student request)) err-unauthorized)
        (asserts! (is-eq (get status request) "open") err-request-closed)
        (map-set ScholarshipRequests request-id
            (merge request { status: "closed" })
        )
        (ok true)
    )
)

(define-public (request-emergency-release (scholarship-id uint))
    (let (
            (scholarship (unwrap! (map-get? Scholarships scholarship-id) err-not-registered))
            (activity (default-to {
                last-activity: u0,
                emergency-request: none,
                emergency-approved: false,
            }
                (map-get? ScholarshipActivity scholarship-id)
            ))
        )
        (asserts! (is-eq tx-sender (get student scholarship)) err-unauthorized)
        (asserts! (get active scholarship) err-invalid-milestone)
        (asserts! (is-none (get emergency-request activity))
            err-already-submitted
        )
        (map-set ScholarshipActivity scholarship-id
            (merge activity { emergency-request: (some burn-block-height) })
        )
        (ok true)
    )
)

(define-public (approve-emergency-release (scholarship-id uint))
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
            (scholarship (unwrap! (map-get? Scholarships scholarship-id) err-not-registered))
            (activity (unwrap! (map-get? ScholarshipActivity scholarship-id)
                err-not-registered
            ))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (asserts! (is-some (get emergency-request activity))
            err-no-emergency-pending
        )
        (asserts! (not (get emergency-approved activity)) err-already-reviewed)
        (let (
                (remaining-amount (/ (get amount scholarship) u2))
                (platform-fee (/ (* remaining-amount (var-get platform-fee-percent)) u100))
                (student-amount (- remaining-amount platform-fee))
            )
            (try! (as-contract (stx-transfer? student-amount (as-contract tx-sender)
                (get student scholarship)
            )))
            (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) contract-owner)))
            (map-set ScholarshipActivity scholarship-id
                (merge activity { emergency-approved: true })
            )
            (ok true)
        )
    )
)

(define-public (refund-inactive-scholarship (scholarship-id uint))
    (let (
            (scholarship (unwrap! (map-get? Scholarships scholarship-id) err-not-registered))
            (activity (unwrap! (map-get? ScholarshipActivity scholarship-id)
                err-not-registered
            ))
            (student-data (unwrap! (map-get? Students (get student scholarship))
                err-not-registered
            ))
        )
        (asserts! (is-eq tx-sender (get donor scholarship)) err-unauthorized)
        (asserts! (get active scholarship) err-invalid-milestone)
        (asserts!
            (> burn-block-height
                (+ (get last-activity activity) (var-get inactivity-threshold))
            )
            err-scholarship-not-inactive
        )
        (let (
                (completed-milestones (get completed-milestones student-data))
                (total-milestones (get total-milestones student-data))
                (milestone-amount (/ (get amount scholarship) (get milestones scholarship)))
                (completed-amount (* completed-milestones milestone-amount))
                (remaining-amount (- (get amount scholarship) completed-amount))
            )
            (if (> remaining-amount u0)
                (try! (as-contract (stx-transfer? remaining-amount (as-contract tx-sender)
                    (get donor scholarship)
                )))
                true
            )
            (map-set Scholarships scholarship-id
                (merge scholarship { active: false })
            )
            (ok remaining-amount)
        )
    )
)

(define-read-only (get-scholarship-activity (scholarship-id uint))
    (ok (map-get? ScholarshipActivity scholarship-id))
)

(define-public (update-inactivity-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set inactivity-threshold new-threshold)
        (ok true)
    )
)

(define-public (create-scholarship-pool
        (student principal)
        (target-amount uint)
        (deadline-blocks uint)
        (milestones uint)
    )
    (let (
            (student-data (unwrap! (map-get? Students student) err-not-registered))
            (pool-id (+ (var-get pool-counter) u1))
            (deadline (+ burn-block-height deadline-blocks))
        )
        (asserts! (>= target-amount (var-get min-stake-amount))
            err-insufficient-funds
        )
        (var-set pool-counter pool-id)
        (map-set ScholarshipPools pool-id {
            creator: tx-sender,
            student: student,
            target-amount: target-amount,
            current-amount: u0,
            deadline: deadline,
            milestones: milestones,
            status: "active",
            created-at: burn-block-height,
        })
        (ok pool-id)
    )
)

(define-public (contribute-to-pool
        (pool-id uint)
        (amount uint)
    )
    (let (
            (pool (unwrap! (map-get? ScholarshipPools pool-id) err-pool-not-found))
            (contribution-key {
                pool-id: pool-id,
                contributor: tx-sender,
            })
        )
        (asserts! (is-eq (get status pool) "active") err-pool-closed)
        (asserts! (< burn-block-height (get deadline pool)) err-pool-closed)
        (asserts! (is-none (map-get? PoolContributions contribution-key))
            err-already-contributed
        )
        (asserts! (>= amount u100) err-insufficient-funds)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set PoolContributions contribution-key {
            amount: amount,
            timestamp: burn-block-height,
        })
        (let ((new-amount (+ (get current-amount pool) amount)))
            (map-set ScholarshipPools pool-id
                (merge pool { current-amount: new-amount })
            )
            (ok new-amount)
        )
    )
)

(define-public (finalize-pool (pool-id uint))
    (let ((pool (unwrap! (map-get? ScholarshipPools pool-id) err-pool-not-found)))
        (asserts! (is-eq (get status pool) "active") err-pool-closed)
        (asserts! (>= burn-block-height (get deadline pool)) err-pool-not-expired)
        (if (>= (get current-amount pool) (get target-amount pool))
            (begin
                (map-set ScholarshipPools pool-id
                    (merge pool { status: "funded" })
                )
                (let ((scholarship-id (+ (var-get scholarship-counter) u1)))
                    (var-set scholarship-counter scholarship-id)
                    (map-set Scholarships scholarship-id {
                        donor: (get creator pool),
                        student: (get student pool),
                        amount: (get current-amount pool),
                        milestones: (get milestones pool),
                        active: true,
                    })
                    (map-set ScholarshipActivity scholarship-id {
                        last-activity: burn-block-height,
                        emergency-request: none,
                        emergency-approved: false,
                    })
                    (ok scholarship-id)
                )
            )
            (begin
                (map-set ScholarshipPools pool-id
                    (merge pool { status: "failed" })
                )
                (ok u0)
            )
        )
    )
)

(define-public (claim-pool-refund (pool-id uint))
    (let (
            (pool (unwrap! (map-get? ScholarshipPools pool-id) err-pool-not-found))
            (contribution-key {
                pool-id: pool-id,
                contributor: tx-sender,
            })
            (contribution (unwrap! (map-get? PoolContributions contribution-key)
                err-not-registered
            ))
        )
        (asserts! (is-eq (get status pool) "failed") err-target-not-met)
        (try! (as-contract (stx-transfer? (get amount contribution) (as-contract tx-sender)
            tx-sender
        )))
        (map-delete PoolContributions contribution-key)
        (ok (get amount contribution))
    )
)

(define-read-only (get-pool-info (pool-id uint))
    (ok (map-get? ScholarshipPools pool-id))
)

(define-read-only (get-pool-contribution
        (pool-id uint)
        (contributor principal)
    )
    (ok (map-get? PoolContributions {
        pool-id: pool-id,
        contributor: contributor,
    }))
)

;; === PERFORMANCE ANALYTICS & ACHIEVEMENT SYSTEM ===
;; Independent feature for tracking student performance and achievements

;; New error constants for achievement system
(define-constant err-achievement-exists (err u122))
(define-constant err-achievement-not-found (err u123))
(define-constant err-invalid-score (err u124))
(define-constant err-achievement-locked (err u125))

;; System configuration variables
(define-data-var achievement-counter uint u0)
(define-data-var min-performance-score uint u60)
(define-data-var max-achievements-per-student uint u50)

;; Student Performance Analytics
(define-map StudentPerformance
    principal
    {
        total-achievements: uint,
        performance-score: uint,
        milestone-completion-rate: uint,
        average-submission-time: uint,
        consistency-streak: uint,
        last-activity-block: uint,
        total-points-earned: uint,
    }
)

;; Achievement Badge System
(define-map Achievements
    uint
    {
        student: principal,
        achievement-type: (string-ascii 30),
        title: (string-ascii 100),
        description: (string-ascii 200),
        points-awarded: uint,
        earned-at: uint,
        verified-by: (optional principal),
        metadata: (string-ascii 150),
    }
)

;; Performance Metrics Tracking
(define-map PerformanceMetrics
    {
        student: principal,
        metric-type: (string-ascii 20),
    }
    {
        value: uint,
        last-updated: uint,
        trend: (string-ascii 10),
    }
)

;; Achievement Templates (predefined achievement types)
(define-map AchievementTemplates
    (string-ascii 30)
    {
        title: (string-ascii 100),
        description: (string-ascii 200),
        points: uint,
        requirements: (string-ascii 150),
        category: (string-ascii 20),
    }
)

;; Public function to award achievement to student
(define-public (award-achievement
        (student principal)
        (achievement-type (string-ascii 30))
        (metadata (string-ascii 150))
    )
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
            (student-data (unwrap! (map-get? Students student) err-not-registered))
            (template (unwrap! (map-get? AchievementTemplates achievement-type)
                err-achievement-not-found
            ))
            (achievement-id (+ (var-get achievement-counter) u1))
            (current-performance (default-to {
                total-achievements: u0,
                performance-score: u0,
                milestone-completion-rate: u0,
                average-submission-time: u0,
                consistency-streak: u0,
                last-activity-block: u0,
                total-points-earned: u0,
            }
                (map-get? StudentPerformance student)
            ))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (asserts!
            (< (get total-achievements current-performance)
                (var-get max-achievements-per-student)
            )
            err-achievement-locked
        )
        (var-set achievement-counter achievement-id)
        (map-set Achievements achievement-id {
            student: student,
            achievement-type: achievement-type,
            title: (get title template),
            description: (get description template),
            points-awarded: (get points template),
            earned-at: burn-block-height,
            verified-by: (some tx-sender),
            metadata: metadata,
        })
        (map-set StudentPerformance student
            (merge current-performance {
                total-achievements: (+ (get total-achievements current-performance) u1),
                total-points-earned: (+ (get total-points-earned current-performance)
                    (get points template)
                ),
                last-activity-block: burn-block-height,
            })
        )
        (ok achievement-id)
    )
)

;; Update student performance metrics
(define-public (update-performance-score
        (student principal)
        (new-score uint)
        (completion-rate uint)
    )
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
            (current-performance (default-to {
                total-achievements: u0,
                performance-score: u0,
                milestone-completion-rate: u0,
                average-submission-time: u0,
                consistency-streak: u0,
                last-activity-block: u0,
                total-points-earned: u0,
            }
                (map-get? StudentPerformance student)
            ))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (asserts! (<= new-score u100) err-invalid-score)
        (asserts! (<= completion-rate u100) err-invalid-score)
        (let (
                (streak (if (>= new-score (var-get min-performance-score))
                    (+ (get consistency-streak current-performance) u1)
                    u0
                ))
            )
            (map-set StudentPerformance student
                (merge current-performance {
                    performance-score: new-score,
                    milestone-completion-rate: completion-rate,
                    consistency-streak: streak,
                    last-activity-block: burn-block-height,
                })
            )
            (ok streak)
        )
    )
)

;; Record specific performance metric
(define-public (record-performance-metric
        (student principal)
        (metric-type (string-ascii 20))
        (value uint)
        (trend (string-ascii 10))
    )
    (let (
            (mentor-data (unwrap! (map-get? Mentors tx-sender) err-not-registered))
        )
        (asserts! (get verified mentor-data) err-unauthorized)
        (map-set PerformanceMetrics
            {
                student: student,
                metric-type: metric-type,
            }
            {
                value: value,
                last-updated: burn-block-height,
                trend: trend,
            }
        )
        (ok true)
    )
)

;; Admin function to create custom achievement template
(define-public (create-achievement-template
        (template-key (string-ascii 30))
        (title (string-ascii 100))
        (description (string-ascii 200))
        (points uint)
        (requirements (string-ascii 150))
        (category (string-ascii 20))
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? AchievementTemplates template-key))
            err-achievement-exists
        )
        (map-set AchievementTemplates template-key {
            title: title,
            description: description,
            points: points,
            requirements: requirements,
            category: category,
        })
        (ok true)
    )
)

;; Read-only functions for performance analytics
(define-read-only (get-student-performance (student principal))
    (ok (map-get? StudentPerformance student))
)

(define-read-only (get-achievement-details (achievement-id uint))
    (ok (map-get? Achievements achievement-id))
)

(define-read-only (get-performance-metric
        (student principal)
        (metric-type (string-ascii 20))
    )
    (ok (map-get? PerformanceMetrics {
        student: student,
        metric-type: metric-type,
    }))
)

(define-read-only (get-achievement-template (template-key (string-ascii 30)))
    (ok (map-get? AchievementTemplates template-key))
)

;; Calculate student performance rank (simplified scoring)
(define-read-only (calculate-student-rank (student principal))
    (let (
            (performance (default-to {
                total-achievements: u0,
                performance-score: u0,
                milestone-completion-rate: u0,
                average-submission-time: u0,
                consistency-streak: u0,
                last-activity-block: u0,
                total-points-earned: u0,
            }
                (map-get? StudentPerformance student)
            ))
        )
        (ok {
            rank-score: (+ 
                (* (get performance-score performance) u2)
                (get total-points-earned performance)
                (* (get consistency-streak performance) u10)
            ),
            performance-level: (if (>= (get performance-score performance) u90)
                "excellent"
                (if (>= (get performance-score performance) u75)
                    "good"
                    (if (>= (get performance-score performance) u60)
                        "satisfactory"
                        "needs-improvement"
                    )
                )
            ),
        })
    )
)

;; Admin functions for system configuration
(define-public (update-min-performance-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-score u100) err-invalid-score)
        (var-set min-performance-score new-score)
        (ok true)
    )
)

(define-public (update-max-achievements-per-student (new-max uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set max-achievements-per-student new-max)
        (ok true)
    )
)

;; Initialize default achievement templates on contract deployment
(map-set AchievementTemplates "first_milestone"
    {
        title: "First Steps",
        description: "Successfully completed your first milestone",
        points: u100,
        requirements: "Complete 1 milestone",
        category: "milestone",
    }
)

(map-set AchievementTemplates "consistent_performer"
    {
        title: "Consistency Champion",
        description: "Maintained high performance for 5 consecutive milestones",
        points: u250,
        requirements: "5 milestone streak",
        category: "consistency",
    }
)

(map-set AchievementTemplates "fast_learner"
    {
        title: "Speed Demon",
        description: "Completed milestones faster than average",
        points: u150,
        requirements: "Above average speed",
        category: "speed",
    }
)

(map-set AchievementTemplates "excellence_award"
    {
        title: "Excellence Award",
        description: "Achieved performance score above 90%",
        points: u300,
        requirements: "90% performance score",
        category: "excellence",
    }
)
