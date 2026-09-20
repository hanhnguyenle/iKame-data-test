# DAX Measures — Product X Dashboard

Tạo 1 bảng riêng không liên kết dữ liệu để chứa toàn bộ measure (khuyến nghị chuẩn PBI, giúp dễ quản lý):
**Model view → Enter Data** → tạo bảng tên `_Measures` với 1 cột placeholder → không cần dữ liệu thật. Sau đó paste từng measure dưới đây vào bảng đó (New Measure).

Giả định relationship đã tạo:
- `dim_user.user_id` → (1:*) → `fact_daily_activity`, `fact_main_function`, `fact_reminder`, `fact_ad_impression`, `fact_app_remove`
- `dim_date.date_key` → (1:*) → `fact_daily_activity.event_date` (active), các fact khác tương tự — nếu bạn để `event_date` là quan hệ active và `install_date`/`remove_date` là inactive, dùng `USERELATIONSHIP()` như ghi chú bên dưới.

---

## 1. Nhóm Acquisition

```dax
Total Installs =
COUNTROWS ( 'mart dim_user' )
```

```dax
Installs (Paid) =
CALCULATE (
    [Total Installs],
    'mart dim_user'[traffic_source_source] <> "organic"
)
```

```dax
Installs (Organic) =
CALCULATE (
    [Total Installs],
    'mart dim_user'[traffic_source_source] = "organic"
)
```

```dax
% Paid Installs =
DIVIDE ( [Installs (Paid)], [Total Installs] )
```

```dax
New Installs (in period) =
CALCULATE (
    [Total Installs],
    USERELATIONSHIP ( 'mart dim_date'[date_key], 'mart dim_user'[install_date] )
)
```
> Dùng measure này khi đặt `dim_date` lên trục X / slicer date và muốn đếm installs THEO NGÀY CÀI ĐẶT — bắt buộc vì quan hệ `dim_date ↔ dim_user.install_date` là quan hệ **inactive** (do `dim_date` đã có quan hệ active với `fact_daily_activity.event_date`). Nếu bạn không đặt slicer ngày, dùng thẳng `[Total Installs]`.

---

## 2. Nhóm Engagement

```dax
DAU =
DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] )
```
> Filter context theo ngày (từ `dim_date` trên trục X) sẽ tự động giới hạn đúng ngày đó vì `fact_daily_activity` có 1 dòng/user/ngày.

```dax
Avg Session per Active User =
DIVIDE (
    SUM ( 'mart fact_daily_activity'[session_count] ),
    DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] )
)
```

```dax
Total Sessions =
SUM ( 'mart fact_daily_activity'[session_count] )
```

```dax
Avg Engagement Time (sec) =
DIVIDE (
    SUM ( 'mart fact_daily_activity'[engagement_time_sec] ),
    DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] )
)
```

```dax
Total Main Function Usage =
COUNTROWS ( 'mart fact_main_function' )
```

```dax
% Users Used Main Function =
DIVIDE (
    CALCULATE ( DISTINCTCOUNT ( 'mart fact_main_function'[user_id] ), ALLSELECTED ( 'mart fact_main_function' ) ),
    [Total Installs]
)
```

```dax
Reminder Show Count =
CALCULATE (
    COUNTROWS ( 'mart fact_reminder' ),
    'mart fact_reminder'[action_name] = "show"
)
```

```dax
Reminder Click Count =
CALCULATE (
    COUNTROWS ( 'mart fact_reminder' ),
    'mart fact_reminder'[action_name] = "click"
)
```

```dax
Reminder CTR =
DIVIDE ( [Reminder Click Count], [Reminder Show Count] )
```

---

## 3. Nhóm Retention / Churn

**Cách tiếp cận**: retention D-N = trong số user cài đặt vào ngày X, có bao nhiêu % còn hoạt động (có dòng trong `fact_daily_activity`) đúng N ngày sau đó. Cần dùng cột `days_since_install` đã tính sẵn trong `fact_daily_activity` (không cần join lại `dim_date`).

```dax
Cohort Size (Installs) =
CALCULATE (
    [Total Installs],
    USERELATIONSHIP ( 'mart dim_date'[date_key], 'mart dim_user'[install_date] )
)
```

```dax
D1 Active Users =
CALCULATE (
    DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] ),
    'mart fact_daily_activity'[days_since_install] = 1
)
```

```dax
D7 Active Users =
CALCULATE (
    DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] ),
    'mart fact_daily_activity'[days_since_install] = 7
)
```

```dax
D30 Active Users =
CALCULATE (
    DISTINCTCOUNT ( 'mart fact_daily_activity'[user_id] ),
    'mart fact_daily_activity'[days_since_install] = 30
)
```

```dax
D1 Retention =
DIVIDE ( [D1 Active Users], [Cohort Size (Installs)] )
```

```dax
D7 Retention =
DIVIDE ( [D7 Active Users], [Cohort Size (Installs)] )
```

```dax
D30 Retention =
DIVIDE ( [D30 Active Users], [Cohort Size (Installs)] )
```

> **Lưu ý quan trọng**: khi đặt các measure D1/D7/D30 Retention lên 1 chart có trục X là `dim_date` (theo ngày cài đặt), PBI sẽ tự filter đúng cohort theo ngày đó nhờ `USERELATIONSHIP` trong `[Cohort Size (Installs)]` — nhưng `[D7 Active Users]` lọc theo `days_since_install` (không phụ thuộc `dim_date`), nên 2 con số này tự nhiên khớp đúng cohort. Nếu bạn dùng trực tiếp `dim_date` làm trục và filter bằng relationship active (`event_date`), retention theo N ngày vẫn đúng vì `days_since_install` đã pre-compute sẵn ở tầng SQL.

```dax
Uninstall Count =
COUNTROWS ( 'mart fact_app_remove' )
```

```dax
Uninstall Rate =
DIVIDE ( [Uninstall Count], [Total Installs] )
```

```dax
Avg Days to Uninstall =
AVERAGE ( 'mart fact_app_remove'[days_since_install] )
```

```dax
Avg Session Count at Remove =
AVERAGE ( 'mart fact_app_remove'[total_number_session_at_remove] )
```

---

## 4. Nhóm Monetization (IAA)

```dax
Total Ad Impressions =
COUNTROWS ( 'mart fact_ad_impression' )
```

```dax
Avg Impressions per User =
DIVIDE (
    [Total Ad Impressions],
    DISTINCTCOUNT ( 'mart fact_ad_impression'[user_id] )
)
```

```dax
Est. Ad Revenue =
SUM ( 'mart fact_ad_impression'[est_revenue_usd] )
```
> `est_revenue_usd` đã được tính sẵn ở tầng SQL (`sql/06_build_mart.sql`, view `mart.fact_ad_impression`) = eCPM ÷ 1000 mỗi dòng — measure này chỉ SUM lại, không cần lookup DAX.

```dax
Est. eCPM Blended =
DIVIDE ( [Est. Ad Revenue] * 1000, [Total Ad Impressions] )
```

```dax
LTV D7 (per user avg) =
VAR ImpressionsD7 =
    CALCULATE (
        SUM ( 'mart fact_ad_impression'[est_revenue_usd] ),
        'mart fact_ad_impression'[days_since_install] <= 7,
        'mart fact_ad_impression'[days_since_install] >= 0
    )
VAR CohortUsers = [Cohort Size (Installs)]
RETURN
    DIVIDE ( ImpressionsD7, CohortUsers )
```
> Đây là công thức trả lời **câu hỏi 3**: LTV(D7) trung bình/user = tổng doanh thu ước tính từ impression trong 7 ngày đầu, chia cho số user trong cohort (install). Đặt measure này trên 1 bảng/matrix có `traffic_source_source` (từ `dim_user`) làm hàng, PBI sẽ tự tính riêng theo từng traffic_source.

```dax
Impr per User D7 =
VAR ImpressionsD7 =
    CALCULATE (
        COUNTROWS ( 'mart fact_ad_impression' ),
        'mart fact_ad_impression'[days_since_install] <= 7,
        'mart fact_ad_impression'[days_since_install] >= 0
    )
VAR CohortUsers = [Cohort Size (Installs)]
RETURN
    DIVIDE ( ImpressionsD7, CohortUsers )
```
> Cột "IMPR./USER (D7)" trong bảng đề xuất CPI — cùng logic với `LTV D7 (per user avg)` ở trên nhưng đếm số impression (`COUNTROWS`) thay vì SUM doanh thu.

```dax
Suggested CPI =
[LTV D7 (per user avg)]
```
> **Đây là ngưỡng hòa vốn tối đa (breakeven CPI), không phải CPI nên trả.** Giá trị cố ý bằng đúng `LTV D7` — nghĩa là "trần": trả cao hơn số này thì lỗ ngay trong 7 ngày đầu (chưa tính chi phí vận hành/margin khác). Tách thành 2 measure riêng (thay vì chỉ dùng `LTV D7` trên bảng) để đặt đúng tên ngữ nghĩa cạnh nhau cho người đọc — đội UA/marketing tự áp thêm hệ số an toàn (VD: chỉ trả 70–80% con số này) khi ra quyết định giá thầu thực tế, measure này không quyết định thay họ. Nếu sau này muốn báo cáo tự trừ margin sẵn, sửa thành `[LTV D7 (per user avg)] * (1 - hệ_số_margin)`.

```dax
Suggested CPI (Display) =
VAR TrafficSource = SELECTEDVALUE ( 'mart dim_user'[traffic_source_source] )
RETURN
    IF (
        TrafficSource = "organic",
        BLANK (),
        [Suggested CPI]
    )
```
> Dùng measure này (thay vì `Suggested CPI` thẳng) trên bảng hiển thị — Organic là traffic miễn phí nên không có ý nghĩa "CPI đề xuất", `BLANK()` khiến Power BI tự hiện "—" ở ô đó thay vì 1 con số gây hiểu lầm là "có thể trả tới mức này cho Organic".

```dax
LTV D7 Color =
VAR CurrentVal = [LTV D7 (per user avg)]
VAR MaxVal =
    CALCULATE ( MAXX ( ALLSELECTED ( 'mart dim_user'[traffic_source_source] ), [LTV D7 (per user avg)] ) )
VAR MinVal =
    CALCULATE ( MINX ( ALLSELECTED ( 'mart dim_user'[traffic_source_source] ), [LTV D7 (per user avg)] ) )
RETURN
    SWITCH (
        TRUE (),
        CurrentVal = MaxVal, "#E8F4EA",
        CurrentVal = MinVal, "#FDE8D8",
        "#FFFFFF"
    )
```
> Mã màu pill cho cột LTV D7: dòng traffic_source có LTV D7 cao nhất tô xanh nhạt, thấp nhất tô cam nhạt, còn lại nền trắng. Gán qua Format visual → chọn cột `LTV D7 (per user avg)` → Cell elements → Background color → Format by **Field value** → `LTV D7 Color`.

---

## 5. Nhóm hỗ trợ định dạng hiển thị (không bắt buộc nhưng nên có)

```dax
Installs (Prior Period) =
CALCULATE (
    [Total Installs],
    DATEADD ( 'mart dim_date'[date_key], -1, MONTH )
)
```

```dax
Installs % Change vs Prior =
DIVIDE ( [Total Installs] - [Installs (Prior Period)], [Installs (Prior Period)] )
```

> Áp dụng pattern tương tự cho các KPI khác cần hiển thị delta (DAU, D7 Retention, Uninstall Rate, Est. Ad Revenue) nếu bạn muốn KPI card có mũi tên tăng/giảm như trong mockup — chỉ cần đổi measure gốc trong `CALCULATE`.

---

## 6. Nhóm Bảng "Chi tiết theo tuần" (So sánh Installs & chất lượng theo tuần)

**Yêu cầu**: 1 bảng Table, mỗi dòng là 1 tuần, hiện Installs, % Paid, D1 Ret., D7 Ret., và cột "Xu hướng" dạng nhãn text phân loại theo quy tắc: volume tăng nhưng D7 retention giảm → cảnh báo riêng.

**Điều kiện bắt buộc trước khi dùng các measure dưới đây**: bảng `'mart dim_date'` phải được đánh dấu **Mark as date table** (Model view → chọn bảng → Table tools → Mark as date table → chọn cột `date_key`), nếu không `STARTOFWEEK`/`ENDOFWEEK`/`DATEADD` sẽ báo lỗi "must be a calendar reference".

```dax
Weekly Installs (This Week) =
CALCULATE (
    [New Installs (in period)],
    DATESBETWEEN (
        'mart dim_date'[date_key],
        STARTOFWEEK ( 'mart dim_date'[date_key] ),
        ENDOFWEEK ( 'mart dim_date'[date_key] )
    )
)
```
> Truyền thẳng cột `'mart dim_date'[date_key]` vào `STARTOFWEEK`/`ENDOFWEEK` — không bọc `MAX()`, vì 2 hàm này cần 1 tham chiếu cột thuộc bảng Date đã đánh dấu Calendar, không nhận giá trị scalar.

```dax
Weekly Installs (Prior Week) =
CALCULATE (
    [Weekly Installs (This Week)],
    DATEADD ( 'mart dim_date'[date_key], -7, DAY )
)
```

```dax
D1 Retention (This Week) =
CALCULATE (
    [D1 Retention],
    DATESBETWEEN (
        'mart dim_date'[date_key],
        STARTOFWEEK ( 'mart dim_date'[date_key] ),
        ENDOFWEEK ( 'mart dim_date'[date_key] )
    )
)
```

```dax
D7 Retention (This Week) =
CALCULATE (
    [D7 Retention],
    DATESBETWEEN (
        'mart dim_date'[date_key],
        STARTOFWEEK ( 'mart dim_date'[date_key] ),
        ENDOFWEEK ( 'mart dim_date'[date_key] )
    )
)
```

```dax
D7 Retention (Prior Week) =
CALCULATE (
    [D7 Retention (This Week)],
    DATEADD ( 'mart dim_date'[date_key], -7, DAY )
)
```

```dax
Installs % Change (WoW) =
DIVIDE (
    [Weekly Installs (This Week)] - [Weekly Installs (Prior Week)],
    [Weekly Installs (Prior Week)]
)
```

```dax
D7 Retention Change (WoW, pts) =
[D7 Retention (This Week)] - [D7 Retention (Prior Week)]
```

```dax
Weekly Trend Label =
VAR InstallsChange = [Installs % Change (WoW)]
VAR D7Change = [D7 Retention Change (WoW, pts)]
RETURN
    SWITCH (
        TRUE (),
        InstallsChange > 0.05 && D7Change < -0.01, "Volume↑ nhưng D7↓",
        D7Change < -0.01, "Cần theo dõi",
        InstallsChange > 0.05 && D7Change >= 0, "Tăng trưởng",
        "Ổn định"
    )
```
> Thứ tự các nhánh trong `SWITCH(TRUE(), ...)` bắt buộc phải giữ nguyên: "Volume↑ nhưng D7↓" phải đứng trước "Cần theo dõi", vì đây là điều kiện đặc thù hơn — nếu đảo thứ tự, nhánh "Cần theo dõi" sẽ nuốt mất mọi trường hợp có D7Change < -0.01, kể cả khi installs đang tăng mạnh. Ngưỡng `0.05` (5%) và `-0.01` (1 điểm %) là ước lượng ban đầu — tự điều chỉnh cho khớp phân bố dữ liệu thật của bạn.

```dax
Weekly Trend Color =
SWITCH (
    [Weekly Trend Label],
    "Ổn định", "#E8F4EA",
    "Tăng trưởng", "#D4EDD9",
    "Volume↑ nhưng D7↓", "#FDE8D8",
    "Cần theo dõi", "#FADCD9",
    "#FFFFFF"
)
```
> Dùng cho conditional formatting nền ô cột "Xu hướng": Format visual → chọn cột `Weekly Trend Label` trong Table → Cell elements → Background color → Format by **Field value** → chọn measure này. Table chuẩn của Power BI không bo tròn thành pill được — nền sẽ là hình chữ nhật, muốn đúng dạng pill bo góc như ảnh mockup cần custom visual hỗ trợ HTML (VD: "HTML Content" trên AppSource).

**Dựng visual Table**:
1. Cột "Tuần": cần 1 cột text ghép sẵn dạng "05/06 – 11/06" — nếu `'mart dim_date'` chưa có cột này, tạo calculated column:
```dax
Week Label =
FORMAT ( STARTOFWEEK ( 'mart dim_date'[date_key] ), "dd/MM" ) & " – " &
FORMAT ( ENDOFWEEK ( 'mart dim_date'[date_key] ), "dd/MM" )
```
2. Các cột còn lại kéo vào Table theo thứ tự: `Week Label`, `Weekly Installs (This Week)`, `% Paid Installs`, `D1 Retention (This Week)`, `D7 Retention (This Week)`, `Weekly Trend Label`
3. Vì Table hiển thị theo từng dòng = 1 tuần, cần đặt `Week Label` (hoặc cột tuần gốc) ở vị trí đầu tiên để Power BI tự nhóm theo tuần correctly — đảm bảo `'mart dim_date'` có 1 cột "Week Number"/"ISO Week" riêng dùng để precise grouping thay vì chỉ dựa vào `Week Label` dạng text (text sort có thể sai thứ tự nếu tuần bắc qua 2 tháng khác nhau).

---

## Ghi chú triển khai

- Tên bảng trong công thức trên viết theo dạng `'mart dim_user'`/`'mart fact_ad_impression'` — khi import, Power BI thường tự đặt tên bảng theo `schema_tablename` hoặc chỉ `tablename` tuỳ cách bạn chọn ở Navigator. Kiểm tra tên bảng thực tế trong Model view và sửa lại tên trong công thức DAX cho khớp (Ctrl+H tìm-thay nếu cần đổi hàng loạt).
- Toàn bộ measure dùng `DIVIDE()` thay vì `/` để tự động trả `BLANK()` khi mẫu số = 0, tránh lỗi chia cho 0 trên chart.
- Measures nhóm Retention phụ thuộc cột `days_since_install` đã tính sẵn ở tầng SQL (`dwh`/`mart`) — không cần tính lại bằng `DATEDIFF` trong DAX.
