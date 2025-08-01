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

(define-data-var scholarship-request-counter uint u0)
(define-data-var bid-counter uint u0)
(define-data-var inactivity-threshold uint u1000)

(define-map ScholarshipActivity
    uint
    {
        last-activity: uint,
        emergency-request: (optional uint),
        emergency-approved: bool,
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
