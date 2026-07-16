export function TodayPhone() {
  return (
    <div className="phone" aria-hidden="true">
      <div className="phone-notch" />
      <div className="phone-screen">
        <div className="phone-status">
          <span>9:41</span>
          <span>●●●</span>
        </div>
        <div className="phone-body">
          <div className="phone-label">Today</div>
          <h3 className="phone-title">Thursday</h3>
          <div className="phone-verdict">
            <strong>On track</strong>
            <span>$38 of $85 daily pace · calm day so far</span>
            <div className="phone-spark" aria-hidden="true">
              <i /><i /><i /><i /><i /><i /><i />
            </div>
          </div>
          <div className="phone-rows">
            <div className="phone-row">
              <div className="phone-dot" style={{ background: "#c4b6f5" }} />
              <div>
                <b>Blue Bottle Coffee</b>
                <small>Coffee · morning</small>
              </div>
              <em>$5.45</em>
            </div>
            <div className="phone-row">
              <div className="phone-dot" style={{ background: "#9bb7ff" }} />
              <div>
                <b>Sweetgreen</b>
                <small>Food · lunch</small>
              </div>
              <em>$14.80</em>
            </div>
            <div className="phone-row">
              <div className="phone-dot" style={{ background: "#7dcea0" }} />
              <div>
                <b>Uber</b>
                <small>Transport</small>
              </div>
              <em>$11.20</em>
            </div>
          </div>
        </div>
        <div className="phone-tabs">
          <span className="active">Today</span>
          <span>Activity</span>
          <span>Insights</span>
          <span>You</span>
        </div>
      </div>
    </div>
  );
}

export function PrivacyPhone() {
  return (
    <div className="phone phone--privacy" aria-hidden="true">
      <div className="phone-notch" />
      <div className="phone-screen">
        <div className="phone-status">
          <span>9:41</span>
          <span>●●●</span>
        </div>
        <div className="phone-body">
          <div className="phone-label">Privacy</div>
          <h3 className="phone-title">Your data never leaves this iPhone</h3>
          <div className="zeros">
            <div className="zero">
              <b>0</b>
              <small>Servers</small>
            </div>
            <div className="zero">
              <b>0</b>
              <small>Trackers</small>
            </div>
            <div className="zero">
              <b>0</b>
              <small>Accounts</small>
            </div>
          </div>
          <p className="privacy-line">
            No cloud sync. No analytics. Export anytime — your backup is yours.
          </p>
        </div>
      </div>
    </div>
  );
}

export function InsightsPhone() {
  return (
    <div className="phone" aria-hidden="true">
      <div className="phone-notch" />
      <div className="phone-screen">
        <div className="phone-status">
          <span>9:41</span>
          <span>●●●</span>
        </div>
        <div className="phone-body">
          <div className="phone-label">Insights</div>
          <h3 className="phone-title">This month</h3>
          <div className="donut-wrap" />
          <div className="legend">
            <span>Food & coffee — 34%</span>
            <span>Transport — 21%</span>
            <span>Groceries — 17%</span>
          </div>
          <div className="phone-rows" style={{ marginTop: 12 }}>
            <div className="phone-row">
              <div className="phone-dot" style={{ background: "#f0c27a" }} />
              <div>
                <b>Netflix</b>
                <small>Due in 2 days</small>
              </div>
              <em>$15.49</em>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
