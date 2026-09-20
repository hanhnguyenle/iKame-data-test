# Dashboard Draft — Sản phẩm X

Mục tiêu: dashboard giúp team dự án theo dõi, đánh giá và phát hiện vấn đề trong vận hành, dựa trên dữ liệu tracking. Cấu trúc bám theo 2 giai đoạn PM đề ra: **Tháng 1-2** (hoàn thiện tính năng + thu hút người dùng) và **Tháng 3+** (tối ưu khai thác qua IAA).

**Nguyên tắc thiết kế**: đi từ tổng quan → chi tiết ở cả cấp độ dashboard (trang Overview trước) và cấp độ từng trang (KPI card tổng quan trên cùng → chart phân tích chi tiết bên dưới). Mỗi trang có filter chung: date range, country, tier, traffic_source (áp dụng where phù hợp).

---

## Trang 0 — Executive Overview

**Mục tiêu**: 1 cái nhìn tổng quan sức khỏe sản phẩm trong 10 giây, để bất kỳ ai (kể cả không phải DA) cũng nắm được tình hình.

**Hàng 1 — KPI cards (so với kỳ trước, có mũi tên tăng/giảm %)**
- New Installs (kỳ hiện tại)
- DAU (Daily Active Users, trung bình kỳ)
- D7 Retention Rate
- Uninstall Rate
- Est. Ad Revenue (kỳ hiện tại)
- Est. eCPM blended

**Hàng 2 — Trend chart**
- Line chart: Installs, DAU theo ngày (2 trục hoặc 2 line chung 1 trục nếu scale gần nhau) — toàn bộ khung 06-07/2023
- Line chart: Ad impressions theo ngày, chia theo ad_format (stacked area hoặc multi-line)

**Hàng 3 — Breakdown nhanh**
- Bar chart: Installs theo traffic_source (organic/network_a/network_b)
- Map hoặc bar chart: Installs theo top 10 country
- Donut/bar: User theo tier (Tier01-04)

**Lý do lựa chọn**: KPI card giúp lãnh đạo/PM nắm nhanh mà không cần đọc chart. Trend chart theo ngày giúp phát hiện bất thường (spike/drop) ngay từ trang đầu — nếu thấy bất thường thì mới cần đi sâu vào trang chi tiết tương ứng.

---

## Trang 1 — Acquisition & Growth

**Mục tiêu**: theo dõi hiệu quả thu hút người dùng (giai đoạn ưu tiên tháng 1-2), trả lời "người dùng đến từ đâu, có chất lượng không".

**Hàng 1 — KPI cards**
- Total Installs (kỳ)
- % Installs from paid (network_a + network_b) vs organic
- Avg Installs/day
- New markets/countries xuất hiện trong kỳ (nếu có)

**Hàng 2 — Tổng quan xu hướng**
- Line/area chart: Installs theo ngày, stack theo traffic_source — phát hiện ngày nào tăng đột biến do campaign nào
- Line chart: Installs theo app_version — phát hiện version nào kéo được nhiều user (liên hệ đến feature release)

**Hàng 3 — Chi tiết theo dimension**
- Bar chart: Installs theo traffic_source x country (matrix hoặc stacked bar) — nhóm nào hiệu quả ở thị trường nào
- Bar chart: Installs theo tier — đối chiếu với chi phí acquire tiềm năng (liên hệ trang Monetization)
- Table: Top 10 country theo installs, kèm % organic vs paid

**Hàng 4 — Funnel/chất lượng**
- Funnel chart: first_open → session_start (ngày đầu) — bao nhiêu % user mở app xong có quay lại dùng session ngay ngày đó
- Bar chart: D1 retention theo traffic_source — network nào mang user "chất lượng" hơn (không chỉ số lượng mà còn giữ chân được)

**Lý do lựa chọn**: câu hỏi 3 của đề bài cần CPI theo traffic_source — trang này cho biết installs bao nhiêu, network nào mang lại nhiều/ít, làm cơ sở đối chiếu với chi phí đề xuất.

---

## Trang 2 — Engagement & Product Health

**Mục tiêu**: đánh giá tính năng nào đang hoạt động tốt/kém (giai đoạn ưu tiên "hoàn thiện tính năng"), user gắn bó với sản phẩm ra sao.

**Hàng 1 — KPI cards**
- Avg session/user/day
- Avg engagement time/user/day
- % user dùng ít nhất 1 main_function trong kỳ
- Reminder CTR (click/show)

**Hàng 2 — Tổng quan xu hướng**
- Line chart: Avg session count & avg engagement time theo ngày — xu hướng tăng/giảm mức độ gắn bó theo thời gian
- Line chart: Số lượt dùng main_function theo ngày (tổng) — có đang tăng trưởng đều không

**Hàng 3 — Chi tiết theo tính năng**
- Bar chart (ranked): Số lượt sử dụng theo function_name (junk_clean, phone_booster, cpu_cooler, power_battery_info, power_saving, widget, home_premium) — tính năng nào phổ biến nhất/ít nhất
- Bar chart: % start action theo function — nếu có action khác ngoài "start" (kiểm tra lại action_type distinct), funnel start→complete nếu data cho phép

**Hàng 4 — Hiệu quả re-engagement (reminder)**
- Funnel chart: show → click → close, theo remind_type (notify/dialog/dialog_analytic)
- Bar chart: CTR theo remind_position (screen_hour, screen_day, reminder, ft_install, ft_uninstall, ft_charger)
- Table: so sánh CTR các loại reminder — loại nào hiệu quả nhất để tối ưu

**Lý do lựa chọn**: đây là trang phục vụ trực tiếp câu hỏi 2 (khuyến nghị cải thiện chất lượng sản phẩm) — cần thấy tính năng nào yếu, reminder nào không hiệu quả để đề xuất cải thiện.

---

## Trang 3 — Retention & Churn

**Mục tiêu**: đánh giá khả năng giữ chân người dùng, phát hiện điểm rơi (churn point).

**Hàng 1 — KPI cards**
- D1 / D7 / D30 Retention Rate (kỳ hiện tại)
- Avg days-to-uninstall
- Uninstall Rate (kỳ)
- Total uninstalls

**Hàng 2 — Tổng quan xu hướng**
- Cohort retention curve: % user còn active theo days_since_install (D0, D1, D3, D7, D14, D30), mỗi cohort là 1 line theo tuần cài đặt
- Line chart: Uninstall theo ngày

**Hàng 3 — Chi tiết theo dimension**
- Retention curve so sánh theo traffic_source (network nào giữ chân user tốt hơn)
- Retention curve so sánh theo tier
- Bar chart: Uninstall rate theo tier/country

**Hàng 4 — Điểm rơi (churn signal)**
- Histogram: phân phối `total_number_session_at_remove` — user thường rời đi sau bao nhiêu session (điểm rơi cụ thể)
- Bar chart: Uninstall theo days_since_install (bucket: 0-1, 2-3, 4-7, 8-14, 15-30, 30+) — giai đoạn nào mất user nhiều nhất

**Lý do lựa chọn**: trực tiếp phục vụ câu hỏi 2 — "cải thiện... sự gắn bó" cần biết chính xác lúc nào/vì sao user rời bỏ để đề xuất can thiệp đúng thời điểm.

---

## Trang 4 — Monetization (IAA)

**Mục tiêu**: theo dõi hiệu quả khai thác quảng cáo (giai đoạn ưu tiên từ tháng 3+), làm cơ sở cho đề xuất CPI (câu hỏi 3).

**Hàng 1 — KPI cards**
- Total Ad Impressions (kỳ)
- Avg impressions/user/day
- Est. Total Ad Revenue (kỳ, dùng bảng eCPM đề cho)
- Est. eCPM blended (weighted theo mix tier/format thực tế)

**Hàng 2 — Tổng quan xu hướng**
- Line/area chart: Impressions theo ngày, stack theo ad_format (banner/interstitial/open_ad)
- Line chart: Est. revenue theo ngày

**Hàng 3 — Chi tiết theo dimension**
- Bar chart: Impressions theo ad_format — format nào chiếm tỷ trọng lớn nhất
- Bar chart: Est. revenue theo tier — tier nào đóng góp doanh thu nhiều nhất (dùng bảng eCPM theo tier đề cho)
- Bar chart: Avg impressions/user theo traffic_source — network nào có user xem quảng cáo nhiều hơn (liên hệ LTV)

**Hàng 4 — Phục vụ đề xuất CPI (câu hỏi 3)**
- Table: LTV(D7) ước tính theo traffic_source — impression/user trong 7 ngày đầu x eCPM tương ứng
- Bar chart: LTV(D7) vs CPI đề xuất, theo traffic_source — so sánh trực quan để justify đề xuất với UA
- Table chi tiết: breakdown LTV(D7) theo traffic_source x tier (vì eCPM lệch rất lớn giữa tier)

**Lý do lựa chọn**: đây là trang trả lời trực tiếp câu hỏi 3 — cần thấy rõ cách tính LTV(D7) ra sao để đề xuất CPI, và có đủ dữ liệu trực quan để thuyết phục bộ phận UA.

---

## Danh sách Calculated Measures cần tạo (tổng hợp toàn dashboard)

### Nhóm Acquisition
- `Total Installs` = COUNTROWS(dim_user) [trong filter context]
- `Installs (Paid)` = COUNTROWS(FILTER(dim_user, traffic_source_source <> "organic"))
- `% Paid Installs` = DIVIDE([Installs (Paid)], [Total Installs])
- `Installs by App Version`, `Installs by Country`, `Installs by Tier` — implicit measure qua group by dimension, không cần DAX riêng

### Nhóm Engagement
- `DAU` = DISTINCTCOUNT(fact_session_daily[user_id]) [theo ngày]
- `Avg Session per User` = DIVIDE(SUM(fact_session_daily[session_count]), DISTINCTCOUNT(fact_session_daily[user_id]))
- `Avg Engagement Time (sec)` = DIVIDE(SUM(fact_engagement_daily[engagement_time_sec]), DISTINCTCOUNT(fact_engagement_daily[user_id]))
- `Total Main Function Usage` = COUNTROWS(fact_main_function)
- `% User Used Main Function` = DIVIDE(DISTINCTCOUNT(fact_main_function[user_id]), [Total Installs])
- `Reminder Show Count`, `Reminder Click Count` = COUNTROWS(FILTER(fact_reminder, action_name = "show"/"click"))
- `Reminder CTR` = DIVIDE([Reminder Click Count], [Reminder Show Count])

### Nhóm Retention/Churn
- `D1 Retention` = DIVIDE(COUNTROWS(FILTER(fact_session_daily, days_since_install = 1)), [Total Installs]) — theo cohort install date tương ứng
- `D7 Retention`, `D30 Retention` — tương tự, đổi ngưỡng days_since_install
- `Uninstall Count` = COUNTROWS(fact_app_remove)
- `Uninstall Rate` = DIVIDE([Uninstall Count], [Total Installs])
- `Avg Days to Uninstall` = AVERAGE(fact_app_remove[days_since_install])
- `Avg Session Count at Remove` = AVERAGE(fact_app_remove[total_number_session_at_remove])

### Nhóm Monetization
- `Total Ad Impressions` = COUNTROWS(fact_ad_impression)
- `Avg Impressions per User` = DIVIDE([Total Ad Impressions], DISTINCTCOUNT(fact_ad_impression[user_id]))
- `Est. Ad Revenue` = SUMX(fact_ad_impression, RELATED(ecpm_table[ecpm_value])) / 1000 — cần bảng eCPM (tier x ad_format) làm lookup table riêng
- `Est. eCPM Blended` = DIVIDE([Est. Ad Revenue] * 1000, [Total Ad Impressions])
- `LTV D7` = SUMX(FILTER(fact_ad_impression, days_since_install <= 7), RELATED(ecpm_table[ecpm_value])) / 1000, tính theo user rồi AVERAGEX theo traffic_source
- `Suggested CPI` = [LTV D7] (theo traffic_source, theo đúng yêu cầu đề bài "CPI tương xứng LTV D7")

### Dimension/lookup table cần bổ sung riêng (không có sẵn trong dwh)
- **`ecpm_lookup`**: tier x ad_format → eCPM value, nhập tay từ bảng đề bài cho (4 tier x 3 format = 12 dòng)

---

## Việc cần làm tiếp theo

- [ ] Xác nhận lại cấu trúc 5 trang + nội dung với reviewer (PM/Manager) nếu cần trước khi build mart
- [ ] Từ danh sách measure trên, xác định các VIEW cần tạo trong schema `mart` (mỗi trang có thể cần 1-2 view riêng, hoặc 1 view lớn theo fact + để Power BI tự tạo measure bằng DAX)
- [ ] Tạo bảng `ecpm_lookup` (dim phụ, không lấy từ raw — nhập tay từ đề bài)
