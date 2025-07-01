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
