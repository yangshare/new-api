package model

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSyncPlanSubscriptionsTx covers the sync semantics for editing a plan:
// total amount override (with clamp-down on amount_used), reset-period
// recomputation of next_reset_time, and scope (only active, non-expired
// subscriptions of the same plan are touched).
func TestSyncPlanSubscriptionsTx(t *testing.T) {
	truncateTables(t)

	now := GetDBTimestamp()
	activeEnd := now + 30*24*3600
	base := now - 3600

	plan := &SubscriptionPlan{
		Id:               9701,
		Title:            "Sync",
		PriceAmount:      10,
		DurationUnit:     SubscriptionDurationMonth,
		DurationValue:    1,
		TotalAmount:      1000,
		QuotaResetPeriod: SubscriptionResetNever,
	}
	seedSubscriptionResetPlan(t, plan)

	// 9801: total shrinks below used -> amount_used clamps to new total.
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9801, UserId: 501, PlanId: plan.Id, AmountTotal: 1000, AmountUsed: 700, StartTime: base, EndTime: activeEnd, Status: "active", LastResetTime: base, NextResetTime: 0})
	// 9802: total grows -> amount_used preserved.
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9802, UserId: 501, PlanId: plan.Id, AmountTotal: 1000, AmountUsed: 300, StartTime: base, EndTime: activeEnd, Status: "active", LastResetTime: base, NextResetTime: 0})
	// 9803: other plan -> untouched.
	otherPlan := &SubscriptionPlan{Id: 9702, Title: "Other", PriceAmount: 1, DurationUnit: SubscriptionDurationMonth, DurationValue: 1, TotalAmount: 500}
	seedSubscriptionResetPlan(t, otherPlan)
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9803, UserId: 502, PlanId: otherPlan.Id, AmountTotal: 500, AmountUsed: 50, StartTime: base, EndTime: activeEnd, Status: "active", LastResetTime: base, NextResetTime: 0})
	// 9804: expired end_time -> untouched.
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9804, UserId: 503, PlanId: plan.Id, AmountTotal: 1000, AmountUsed: 900, StartTime: now - 7200, EndTime: now - 1, Status: "active", LastResetTime: base, NextResetTime: 0})
	// 9805: cancelled -> untouched.
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9805, UserId: 504, PlanId: plan.Id, AmountTotal: 1000, AmountUsed: 400, StartTime: base, EndTime: activeEnd, Status: "cancelled", LastResetTime: base, NextResetTime: 0})

	// New plan config: total 500, monthly reset.
	updated := &SubscriptionPlan{
		Id:               plan.Id,
		Title:            "Sync",
		PriceAmount:      10,
		DurationUnit:     SubscriptionDurationMonth,
		DurationValue:    1,
		TotalAmount:      500,
		QuotaResetPeriod: SubscriptionResetMonthly,
	}

	t.Run("nil tx is rejected", func(t *testing.T) {
		res, err := SyncPlanSubscriptionsTx(nil, updated, now)
		require.Error(t, err)
		assert.Nil(t, res)
	})

	res, err := SyncPlanSubscriptionsTx(DB, updated, now)
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, plan.Id, res.PlanId)
	assert.Equal(t, 2, res.MatchedCount)
	assert.Equal(t, 2, res.SyncedCount)
	assert.Equal(t, 1, res.UserCount)
	assert.Equal(t, []int{501}, res.AffectedUserIds)

	// 9801: used 700 clamped down to new total 500; next_reset recomputed.
	s1 := getSubscriptionResetSub(t, 9801)
	assert.EqualValues(t, 500, s1.AmountTotal)
	assert.EqualValues(t, 500, s1.AmountUsed)
	assert.Equal(t, calcNextResetTime(time.Unix(base, 0), updated, activeEnd), s1.NextResetTime)

	// 9802: used 300 preserved, total now 500; next_reset recomputed too.
	s2 := getSubscriptionResetSub(t, 9802)
	assert.EqualValues(t, 500, s2.AmountTotal)
	assert.EqualValues(t, 300, s2.AmountUsed)
	assert.Equal(t, calcNextResetTime(time.Unix(base, 0), updated, activeEnd), s2.NextResetTime)

	// Untouched records keep original amount_used and NextResetTime.
	s3 := getSubscriptionResetSub(t, 9803)
	assert.EqualValues(t, 50, s3.AmountUsed)
	assert.EqualValues(t, 0, s3.NextResetTime)
	assert.EqualValues(t, 900, getSubscriptionResetSub(t, 9804).AmountUsed)
	assert.EqualValues(t, 400, getSubscriptionResetSub(t, 9805).AmountUsed)
}

// TestSyncPlanSubscriptionsTxUnlimitedPlan verifies that a zero (unlimited)
// total never clamps amount_used, and that switching the reset period to
// "never" zeroes next_reset_time.
func TestSyncPlanSubscriptionsTxUnlimitedPlan(t *testing.T) {
	truncateTables(t)

	now := GetDBTimestamp()
	activeEnd := now + 30*24*3600
	base := now - 3600

	plan := &SubscriptionPlan{
		Id:               9711,
		Title:            "Unlimited",
		PriceAmount:      10,
		DurationUnit:     SubscriptionDurationMonth,
		DurationValue:    1,
		TotalAmount:      0,
		QuotaResetPeriod: SubscriptionResetMonthly,
	}
	seedSubscriptionResetPlan(t, plan)
	seedSubscriptionResetSub(t, &UserSubscription{Id: 9811, UserId: 511, PlanId: plan.Id, AmountTotal: 0, AmountUsed: 999999, StartTime: base, EndTime: activeEnd, Status: "active", LastResetTime: base, NextResetTime: now + 10})

	updated := &SubscriptionPlan{Id: plan.Id, Title: "Unlimited", DurationUnit: SubscriptionDurationMonth, DurationValue: 1, TotalAmount: 0, QuotaResetPeriod: SubscriptionResetNever}

	res, err := SyncPlanSubscriptionsTx(DB, updated, now)
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, 1, res.SyncedCount)

	s := getSubscriptionResetSub(t, 9811)
	assert.Zero(t, s.AmountTotal)              // unlimited preserved
	assert.EqualValues(t, 999999, s.AmountUsed) // never clamped when total is 0
	assert.Zero(t, s.NextResetTime)            // "never" period -> no reset
}

// TestSyncPlanSubscriptionsTxNoMatch verifies an empty plan is a no-op success.
func TestSyncPlanSubscriptionsTxNoMatch(t *testing.T) {
	truncateTables(t)

	now := GetDBTimestamp()
	plan := &SubscriptionPlan{Id: 9721, Title: "Empty", PriceAmount: 10, DurationUnit: SubscriptionDurationMonth, DurationValue: 1, TotalAmount: 100}
	seedSubscriptionResetPlan(t, plan)

	res, err := SyncPlanSubscriptionsTx(DB, plan, now)
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Zero(t, res.MatchedCount)
	assert.Empty(t, res.AffectedUserIds)
}
