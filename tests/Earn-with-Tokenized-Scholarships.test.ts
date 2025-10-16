
import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const contractOwner = accounts.get("deployer")!;
const mentor1 = accounts.get("wallet_1")!;
const student1 = accounts.get("wallet_2")!;
const student2 = accounts.get("wallet_3")!;

const contractName = "Earn-with-Tokenized-Scholarships";

describe("EduFund Smart Contract Tests", () => {
  beforeEach(() => {
    // Reset simnet state before each test
    simnet.mineEmptyBlocks(1);
  });

  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  describe("Basic Contract Functions", () => {
    it("allows student registration", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "register-student",
        [Cl.stringAscii("Alice Smith"), Cl.stringAscii("Computer Science"), Cl.uint(10)],
        student1
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("allows mentor registration", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "register-mentor",
        [Cl.stringAscii("Dr. Johnson")],
        mentor1
      );
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Performance Analytics & Achievement System", () => {
    beforeEach(() => {
      // Setup: Register student and mentor, verify mentor
      simnet.callPublicFn(
        contractName,
        "register-student",
        [Cl.stringAscii("Alice Smith"), Cl.stringAscii("Computer Science"), Cl.uint(10)],
        student1
      );
      
      simnet.callPublicFn(
        contractName,
        "register-mentor",
        [Cl.stringAscii("Dr. Johnson")],
        mentor1
      );
      
      simnet.callPublicFn(
        contractName,
        "verify-mentor",
        [Cl.principal(mentor1)],
        contractOwner
      );
    });

    describe("Achievement Templates", () => {
      it("retrieves default achievement templates", () => {
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-achievement-template",
          [Cl.stringAscii("first_milestone")],
          student1
        );
        expect(result).toBeOk(
          Cl.some(
            Cl.tuple({
              title: Cl.stringAscii("First Steps"),
              description: Cl.stringAscii("Successfully completed your first milestone"),
              points: Cl.uint(100),
              requirements: Cl.stringAscii("Complete 1 milestone"),
              category: Cl.stringAscii("milestone"),
            })
          )
        );
      });

      it("allows contract owner to create custom achievement template", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "create-achievement-template",
          [
            Cl.stringAscii("custom_badge"),
            Cl.stringAscii("Custom Achievement"),
            Cl.stringAscii("A special custom achievement"),
            Cl.uint(200),
            Cl.stringAscii("Custom requirements"),
            Cl.stringAscii("custom")
          ],
          contractOwner
        );
        expect(result).toBeOk(Cl.bool(true));
      });

      it("prevents non-owners from creating achievement templates", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "create-achievement-template",
          [
            Cl.stringAscii("unauthorized_badge"),
            Cl.stringAscii("Unauthorized Achievement"),
            Cl.stringAscii("Should not be created"),
            Cl.uint(100),
            Cl.stringAscii("Unauthorized"),
            Cl.stringAscii("invalid")
          ],
          mentor1
        );
        expect(result).toBeErr(Cl.uint(100)); // err-owner-only
      });
    });

    describe("Performance Tracking", () => {
      it("allows verified mentors to update student performance scores", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "update-performance-score",
          [Cl.principal(student1), Cl.uint(85), Cl.uint(80)],
          mentor1
        );
        expect(result).toBeOk(Cl.uint(1)); // consistency streak
      });

      it("prevents unverified mentors from updating performance", () => {
        // Register but don't verify second mentor
        const mentor2 = accounts.get("wallet_4")!;
        simnet.callPublicFn(
          contractName,
          "register-mentor",
          [Cl.stringAscii("Unverified Mentor")],
          mentor2
        );

        const { result } = simnet.callPublicFn(
          contractName,
          "update-performance-score",
          [Cl.principal(student1), Cl.uint(85), Cl.uint(80)],
          mentor2
        );
        expect(result).toBeErr(Cl.uint(105)); // err-unauthorized
      });

      it("validates performance score bounds", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "update-performance-score",
          [Cl.principal(student1), Cl.uint(150), Cl.uint(80)],
          mentor1
        );
        expect(result).toBeErr(Cl.uint(124)); // err-invalid-score
      });
    });

    describe("Achievement Awards", () => {
      it("allows verified mentors to award achievements", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "award-achievement",
          [
            Cl.principal(student1),
            Cl.stringAscii("first_milestone"),
            Cl.stringAscii("Completed intro course")
          ],
          mentor1
        );
        expect(result).toBeOk(Cl.uint(1)); // achievement ID
      });

      it("prevents awarding non-existent achievement types", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "award-achievement",
          [
            Cl.principal(student1),
            Cl.stringAscii("non_existent_badge"),
            Cl.stringAscii("Should fail")
          ],
          mentor1
        );
        expect(result).toBeErr(Cl.uint(123)); // err-achievement-not-found
      });
    });

    describe("Performance Metrics", () => {
      it("allows recording performance metrics", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "record-performance-metric",
          [
            Cl.principal(student1),
            Cl.stringAscii("assignment_score"),
            Cl.uint(92),
            Cl.stringAscii("upward")
          ],
          mentor1
        );
        expect(result).toBeOk(Cl.bool(true));
      });

      it("retrieves performance metrics", () => {
        // First record a metric
        const recordResult = simnet.callPublicFn(
          contractName,
          "record-performance-metric",
          [
            Cl.principal(student1),
            Cl.stringAscii("quiz_average"),
            Cl.uint(88),
            Cl.stringAscii("stable")
          ],
          mentor1
        );
        expect(recordResult.result).toBeOk(Cl.bool(true));

        // Then retrieve it
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-performance-metric",
          [Cl.principal(student1), Cl.stringAscii("quiz_average")],
          student1
        );
        
        // Verify we got some metric data back (function works correctly)
        expect(result).toBeOk(expect.anything());
      });
    });

    describe("Student Performance Analytics", () => {
      it("tracks student performance data", () => {
        // Award an achievement to generate performance data
        const awardResult = simnet.callPublicFn(
          contractName,
          "award-achievement",
          [
            Cl.principal(student1),
            Cl.stringAscii("first_milestone"),
            Cl.stringAscii("First achievement")
          ],
          mentor1
        );
        expect(awardResult.result).toBeOk(Cl.uint(1)); // achievement ID

        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-student-performance",
          [Cl.principal(student1)],
          student1
        );
        
        // Verify we got performance data back (function works correctly)
        expect(result).toBeOk(expect.anything());
      });

      it("calculates student performance rank", () => {
        // Set up performance data
        simnet.callPublicFn(
          contractName,
          "update-performance-score",
          [Cl.principal(student1), Cl.uint(95), Cl.uint(90)],
          mentor1
        );

        const { result } = simnet.callReadOnlyFn(
          contractName,
          "calculate-student-rank",
          [Cl.principal(student1)],
          student1
        );
        
        const rankResult = result as any;
        expect(rankResult).toBeOk(
          Cl.tuple({
            "rank-score": Cl.uint(200), // 95 * 2 + 0 points + 1 * 10
            "performance-level": Cl.stringAscii("excellent"),
          })
        );
      });
    });

    describe("Admin Functions", () => {
      it("allows contract owner to update min performance score", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "update-min-performance-score",
          [Cl.uint(70)],
          contractOwner
        );
        expect(result).toBeOk(Cl.bool(true));
      });

      it("prevents non-owners from updating min performance score", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "update-min-performance-score",
          [Cl.uint(70)],
          mentor1
        );
        expect(result).toBeErr(Cl.uint(100)); // err-owner-only
      });

      it("allows contract owner to update max achievements per student", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "update-max-achievements-per-student",
          [Cl.uint(25)],
          contractOwner
        );
        expect(result).toBeOk(Cl.bool(true));
      });
    });
  });
});
