# [TECHNICAL] Data Quality Check Log — Project X

> Đây là bản ghi kỹ thuật chi tiết (SQL, tên bảng, tên script) dùng để trace lại quá trình xử lý và audit code khi cần. Bản dành cho người đọc không chuyên kỹ thuật (báo cáo, phụ lục) xem tại `data_quality_summary.md`.

Nguồn: `sql/03_data_quality_check.sql`
Layer kiểm tra: `raw.*` (trước khi model sang `dwh`)
Ngày thực hiện: 2026-09-18

---

## 1. Row count sanity (raw vs source CSV)

| Table | Expected rows (wc -l -1) | Notes |
|---|---:|---|
| first_open | 136,324 | |
| session_start | 321,169 | |
| user_engagement | 322,708 | |
| main_function | 707,743 | |
| reminder | 459,974 | |
| ad_impression | 1,016,168 | |
| app_remove | 70,625 | |

(Kết quả loaded_rows thực tế: xem output query `02_import_raw_data.sql` phần cuối / `03_data_quality_check.sql` mục 1.)

---

## 2. Full-row duplicate check

**Phương pháp**: duplicate được định nghĩa là **toàn bộ các cột business giống hệt nhau** (không chỉ `user_id` hay `user_id + event_date`), vì:
- 1 user có thể xoá app rồi cài lại → tạo `first_open` mới hợp lệ với `event_timestamp` khác.
- 1 user có thể có nhiều session/engagement/ad_impression hợp lệ trong cùng 1 ngày.
- Chỉ khi **mọi cột kể cả `event_timestamp` (đơn vị micro giây)** trùng khớp tuyệt đối giữa 2+ dòng thì mới coi là lỗi tracking (không thể là 2 sự kiện tự nhiên khác nhau xảy ra đúng cùng 1 micro giây).

### Kết quả tổng hợp (extra_rows = số dòng dư nếu dedupe)

| Table | Extra rows (duplicate) | % of total rows |
|---|---:|---:|
| first_open | 7,569 | ~5.55% (7,569 / 136,324) |
| app_remove | 0 | 0% |
| session_start | 0 | 0% |
| user_engagement | 0 | 0% |
| main_function | 0 | 0% |
| reminder | 0 | 0% |
| **ad_impression** | **31,935** | ~3.14% (31,935 / 1,016,168) |

→ Chỉ 2/7 bảng có vấn đề: `first_open` và `ad_impression`. 5 bảng còn lại sạch tuyệt đối ở mức full-row.

---

### 2a. `first_open` — CONFIRMED true duplicate

**Bằng chứng** (sample từ query 2i, xem ảnh gốc): nhiều nhóm có cùng `user_id` + cùng `event_timestamp` (khớp đến micro giây) lặp lại 2–5 lần, toàn bộ các cột còn lại (app_version, country, tier, city, language, os_version, brand, traffic_source) cũng giống hệt.

Ví dụ (từ sample thực tế):

| event_date | event_timestamp | user_id | app_version | country | tier | dup_count |
|---|---|---|---|---|---|---:|
| 2023-07-10 | 1688956798192000 | 001240b9533fdc8d31a137733db54449 | 3.59999990463257 | Mexico | Tier03 | 3 |
| 2023-07-31 | 1690816104707000 | 002f15e8d48bccaf09375d05f7a14412 | 8.19999980926514 | Indonesia | Tier03 | 5 |
| 2023-07-31 | 1690807992604000 | 003117c95b10f274d56afbfbd7472c9c | 3.5 | Philippines | Tier03 | 2 |
| 2023-07-17 | 1689602456691000 | 004652d96d004cb28f08c1113bfd9b97 | 8 | Indonesia | Tier03 | 3 |
| 2023-07-20 | 1689870906965000 | 008332060f7ef94bc41658a7822200c3 | 8.19999980926514 | India | Tier04 | 3 |
| 2023-07-18 | 1689680362419000 | 00a59a9057978858f80459714fd076d8 | 8.19999980926514 | Indonesia | Tier03 | 2 |

**Kết luận**: đây là event `first_open` bị **track/gửi trùng lặp** (client-side re-fire, có thể do retry logic của SDK analytics khi mất mạng, hoặc double-init SDK) — không phải hành vi "cài lại app" thật (vì reinstall thật sẽ cho `event_timestamp` khác nhau, cách nhau tối thiểu vài giờ/ngày, không trùng đến micro giây).

**Xử lý đề xuất cho tầng `dwh`**: dedupe theo full business key (giữ 1 dòng/nhóm duplicate, ví dụ dùng `ROW_NUMBER() OVER (PARTITION BY <all business cols> ORDER BY event_timestamp) = 1`) khi build `dwh.dim_user`.

---

### 2a-bis. `first_open` — residual duplicate: geo field inconsistency (sau khi dedupe full-row)

Sau khi loại full-row duplicate (mục 2a), phát hiện thêm 2 nhóm case còn sót — cùng `user_id` + `event_timestamp` (trùng đến micro giây, không thể là 2 sự kiện thật khác nhau) nhưng lệch ở các cột **geo**:

**Case 1 — chỉ lệch `city`** (9 user, xem sample trước đó): mọi cột khác giống hệt, chỉ `city` khác nhau (vd. "New Town" vs "Siliguri", cùng country=India, tier=Tier04). → Khả năng: lỗi geolocation trả về city không nhất quán cho cùng 1 IP/request.

**Case 2 — lệch cả `country` + `tier` + `city`** (2 user còn lại sau khi xử lý case 1): ví dụ user `0ca570dfd7d6016ab5176108998e42df` có 2 dòng cùng timestamp `1689695597291000` — 1 dòng `country=India, tier=Tier04, city=Hapur`, 1 dòng `country=United States, tier=Tier01, city=NULL`. Tương tự user `7a4893d0947b5f18abf72d26f449a1ee`: `country=Iran, tier=Tier04, city=Tabriz` vs `country=United States, tier=Tier01, city=NULL`.

**Pattern nhận thấy**: dòng "United States / Tier01" luôn đi kèm `city = NULL` — dấu hiệu của geolocation ở mức coarse-grained (chỉ xác định được quốc gia, không xác định được thành phố), khả năng cao do **VPN/proxy** (IP exit node ở US) trong khi vị trí thiết bị/SIM thực tế ở nước khác.

**Xử lý**: mở rộng business key ở bước dedupe loại bỏ cả `country`, `tier`, `city` (không chỉ riêng `city`); tie-break ưu tiên giữ dòng có `city IS NOT NULL` (geolocation chi tiết hơn, đáng tin hơn dòng chỉ xác định ở mức country qua VPN). Đã cập nhật trong `sql/04_dedupe_raw.sql`.

**Lưu ý cho phân tích sau này**: vì `country`/`tier` là dimension quan trọng dùng trong câu hỏi 3 (CPI theo tier), các user có geo conflict kiểu VPN này (số lượng rất nhỏ, ~2/136,324 user) có thể khiến `country`/`tier` không phản ánh đúng 100% vị trí thật — chấp nhận sai số này vì tỷ lệ không đáng kể.

---

### 2b. `ad_impression` — CONFIRMED true duplicate

**Bằng chứng** (sample từ query 2j, xem ảnh gốc): tương tự, nhiều nhóm cùng `user_id` + `event_timestamp` (micro giây) + `params_ad_format` lặp lại 2–6 lần.

Ví dụ (từ sample thực tế):

| event_date | event_timestamp | user_id | country | tier | ad_format | dup_count |
|---|---|---|---|---|---|---:|
| 2023-07-22 | 1690042494730001 | 0009fd34972124d7323b10bfdc2be80a | Algeria | Tier04 | banner | 6 |
| 2023-06-14 | 1686746651919000 | 00132d5a7dcf5e84be65e3a59e49d799 | Indonesia | Tier03 | interstitial | 2 |
| 2023-06-26 | 1687797004353000 | 0043b437f2bee5ff0129fd67d98650b3 | India | Tier04 | open_ad | 4 |
| 2023-07-31 | 1690809601258001 | 005b3af92187fe3d8bb45304d97b18dc | India | Tier04 | interstitial | 3 |
| 2023-07-20 | 1689871509548000 | 006d6019a7fd5e78fe39da02691c3b99 | Congo | Tier04 | banner | 2 |

Lưu ý: cùng user `006d6019a7fd5e78fe39da02691c3b99` trong ảnh sample có cả dòng `banner` duplicate 2 lần **và** các dòng `interstitial` khác timestamp (1689871514285002, 1689871531912004) không duplicate — cho thấy pipeline chỉ lặp một số event cụ thể, không phải toàn bộ traffic của user đó bị nhân đôi hệ thống.

**Kết luận**: cùng bản chất lỗi tracking như `first_open` — SDK/pipeline ghi log ad_impression bị bắn trùng ở một số thời điểm.

**Cần điều tra thêm** (query đã viết sẵn trong `03_data_quality_check.sql`, mục 2j — phần "concentrated on specific dates" / "specific app_version"): kiểm tra duplicate có dồn vào 1 ngày/1 app_version cụ thể (dấu hiệu lỗi 1 bản build) hay rải đều (nhiễu ngẫu nhiên của hệ thống tracking). *(Chưa chạy — cần bổ sung kết quả khi có.)*

**Xử lý đề xuất cho tầng `dwh`**: dedupe theo full business key khi build `dwh.fact_ad_impression`, tương tự first_open — dùng `ROW_NUMBER()` giữ 1 dòng/nhóm.

**Lưu ý khi tính doanh thu (câu hỏi 3 — CPI/LTV)**: nếu không dedupe, số lượt impression bị **overcount ~3.14%**, dẫn đến LTV D7 ước tính bị thổi phồng tương ứng → đề xuất CPI cho UA sẽ cao hơn thực tế. Bắt buộc phải dedupe trước khi tính eCPM revenue.

---

## 3. Các bảng sạch (0 full-row duplicate)

`app_remove`, `session_start`, `user_engagement`, `main_function`, `reminder` — không phát hiện duplicate toàn phần. Không cần xử lý dedupe cho các bảng này ở bước `dwh`.

Các mục còn lại của data quality check (null/blank rate, referential integrity, event trước ngày install, date range, categorical sanity, numeric castability, timestamp format) đã được review — không phát hiện vấn đề đáng kể ngoài duplicate nêu trên.

---

## 4. Xử lý dedupe (đã thực hiện)

Script: `sql/04_dedupe_raw.sql`

**Phương pháp**: không sửa/xoá trực tiếp trong bảng `raw` gốc (giữ nguyên để audit/đối chiếu về sau). Thay vào đó tạo 2 bảng mới: `raw.first_open_clean`, `raw.ad_impression_clean`.

**`ad_impression_clean`**: dedupe 1 bước — `ROW_NUMBER() OVER (PARTITION BY <toàn bộ cột business> ORDER BY (SELECT NULL)) = 1`. Loại đúng 31,935 dòng thừa đã xác định ở mục 2b.

**`first_open_clean`**: dedupe 2 bước (do phát hiện residual case ở mục 2a-bis khi build `dwh.dim_user` — xem mục 6 bên dưới):
1. **Bước 1**: loại full-row duplicate (business key gồm tất cả cột kể cả `city`) — loại 7,569 dòng.
2. **Bước 2**: loại tiếp các dòng chỉ khác nhau ở geo field (`country`/`tier`/`city`) nhưng cùng `user_id` + `event_timestamp` — business key bỏ hẳn `country`/`tier`/`city`, tie-break ưu tiên dòng có `city IS NOT NULL` trước (geolocation chi tiết hơn, ít khả năng là VPN/proxy artifact — xem chi tiết mục 2a-bis).

Kết quả cuối: `raw.first_open_clean` đảm bảo đúng 1 dòng/`user_id` (điều kiện bắt buộc để dùng làm PK cho `dwh.dim_user`).

**Quy ước cho bước `dwh`**: khi build `dwh.dim_user` và `dwh.fact_ad_impression`, join/select từ `raw.first_open_clean` và `raw.ad_impression_clean` — không dùng bảng `raw.first_open`/`raw.ad_impression` gốc. 5 bảng còn lại dùng thẳng `raw.*` vì đã sạch.

---

## 5. Kiến trúc 3 tầng (raw → dwh → mart)

Quyết định trong lúc modeling — thêm schema thứ 3 `mart` bên cạnh `raw`/`dwh` đã có:

- **`raw`** — bản sao text thuần của CSV nguồn, không cast type, không dedupe (trừ 2 bảng `*_clean` ở mục 4).
- **`dwh`** — model chuẩn dùng chung: `DIM_DATE`, `DIM_USER`, `FACT_*`. Vật lý hoá dưới dạng TABLE (không phải VIEW) để PBI refresh nhanh, không phải tính lại từ raw mỗi lần. Đúng kiểu dữ liệu (dùng `TRY_CAST`), đúng grain, đã dedupe. Đây là 1 nguồn sự thật duy nhất, không chứa logic riêng của từng dashboard page.
- **`mart`** (schema mới thêm — `sql/01b_add_mart_schema.sql`) — chứa các VIEW "report-ready", mỗi view phục vụ 1 mục đích/1 page dashboard cụ thể (retention, engagement, monetization, UA funnel...). **Power BI chỉ import từ `mart`**, không đụng trực tiếp vào `dwh` hay `raw` — giữ tách biệt giữa model dùng chung và logic nghiệp vụ riêng từng báo cáo.

Script `dwh`: `sql/05_build_dwh.sql`. Tạo `DIM_DATE` (calendar 2023-05-25 → 2023-08-07, có buffer quanh khung data thật 06-07/2023 để tính `days_since_install` không lệch biên), `DIM_USER` (1 dòng/user từ `first_open_clean`, Type-0, không SCD), và 6 FACT table (`fact_app_remove`, `fact_session_daily`, `fact_engagement_daily`, `fact_main_function`, `fact_reminder`, `fact_ad_impression`) — mỗi fact LEFT JOIN `dim_user` để lấy sẵn cột derived `days_since_install`.

---

## 6. Sự cố kỹ thuật gặp khi build `dwh` (đã xử lý)

**Lỗi 1 — PK trên cột nullable**: `dim_date.date_key` tạo từ `CAST()` bị SQL Server suy ra kiểu nullable dù không có NULL thực tế → lỗi `Cannot define PRIMARY KEY constraint on nullable column`. Xử lý: thêm `ALTER TABLE dwh.dim_date ALTER COLUMN date_key DATE NOT NULL` trước khi tạo PK.

**Lỗi 2 — duplicate key khi tạo PK cho `dim_user`**: phát hiện `raw.first_open_clean` (dù đã dedupe full-row) vẫn còn user trùng `user_id`. Điều tra cho thấy đây chính là case "residual geo inconsistency" ở mục 2a-bis — cùng 1 sự kiện install (timestamp trùng micro giây) nhưng bị ghi nhận 2 giá trị geo khác nhau. Đã xử lý bằng cách mở rộng logic dedupe ở `04_dedupe_raw.sql` (xem mục 4, bước 2).

**Lỗi 3 — `session_start`/`user_engagement` không phải 1 dòng/user/ngày như giả định ban đầu**: sau khi build `mart.fact_daily_activity` (FULL OUTER JOIN 2 fact này), phát hiện 27,578 cặp `(user_id, event_date)` duplicate ở `fact_session_daily` và 24,515 cặp ở `fact_engagement_daily`. Điều tra 1 case cụ thể (`user_id = 0005e1381c7512e8c05c7327233cbf9e`) cho thấy: (1) `event_count`/`engagement_time` KHÁC NHAU giữa các dòng cùng user/ngày (vd session_count 3 vs 6 cùng ngày 2023-07-12; engagement_time 2.950 vs 2.471 cùng ngày 2023-07-12) — không phải giá trị giống hệt như case first_open/ad_impression; (2) đối chiếu `raw.session_start` cho thấy các dòng này còn khác cả `city`, và có ngày khác cả `country`/`tier` (Indonesia/Tier03 vs United States/Tier01) — cùng pattern VPN/multi-device đã thấy ở mục 2a-bis, nhưng ở đây không có `event_timestamp` để chứng minh "cùng 1 sự kiện" như first_open. Vì giá trị đo lường (`session_count`/`engagement_time`) khác nhau thực sự giữa các dòng, kết luận đây là **nhiều lượt ghi nhận thật trong cùng ngày** (không phải lỗi tracking bắn trùng), nên xử lý bằng `SUM()` theo `(user_id, event_date)` thay vì dedupe loại bỏ. Đã sửa `05_build_dwh.sql`: `fact_session_daily`/`fact_engagement_daily` giờ group theo `(user_id, event_date)` với `SUM(event_count)`/`SUM(engagement_time)` trước khi join `dim_user`. Kết quả: `fact_session_daily` giảm từ 321,169 → 292,964 dòng, `fact_engagement_daily` từ 322,708 → 290,957 dòng (số dòng giảm do gộp, tổng giá trị đo lường được bảo toàn).

**Phát hiện 4 — user "mồ côi" (orphan) trong các FACT: chủ yếu là bug tracking ở app_version 8.2, không phải left-censoring như giả thuyết ban đầu**: sau khi build `dwh`, các bảng FACT có từ 1,922 đến 19,573 dòng không join được với `dim_user` (`days_since_install IS NULL`), tổng cộng **4,986 user distinct** bị ảnh hưởng trên ít nhất 1 bảng (~3.7% tổng 128,746 user).

Giả thuyết ban đầu (left-censoring — user cài trước 01/06/2023, ngoài phạm vi `first_open`) **bị bác bỏ** sau khi kiểm tra kỹ hơn: số user orphan theo tuần **tăng dần** suốt kỳ (tuần 23/06: 31 user → tuần 23/07: 971 user), ngược với xu hướng giảm dần mà left-censoring thuần túy phải cho thấy (quần thể user cũ phải co lại theo thời gian do churn, không tăng). Lấy mẫu 1 user orphan cụ thể xác nhận: user này hoàn toàn không tồn tại trong `raw.first_open` (kể cả bản gốc chưa dedupe, exact/trim/case-insensitive match đều 0 dòng), độ dài `user_id` bình thường (32 ký tự, đúng chuẩn hash) — loại trừ khả năng lỗi định dạng/join.

Kiểm tra `app_version` của user orphan (dùng `raw.main_function` đối chiếu `NOT EXISTS` với `raw.first_open`) cho thấy: **1,978 / 2,179 user orphan (≈91%) tập trung vào duy nhất 1 version: `8.19999980926514` (≈8.2)**. Kết luận: đây là **bug tracking ở app_version 8.2** — SDK ghi nhận được các event khác (main_function, session, engagement...) bình thường, nhưng event `first_open` không được gửi/lưu thành công cho phần lớn user cài đặt bằng version này. Đây là vấn đề vận hành thực sự (không chỉ là nhiễu dữ liệu), đáng đưa vào report như 1 khuyến nghị cho team kỹ thuật (kiểm tra lại tracking SDK ở bản 8.2).

**Cách xử lý ở tầng dwh/mart**: không sửa gì — `LEFT JOIN` hiện tại đã đúng, để `install_date`/`days_since_install` là NULL cho các user này là chính xác (không có cách nào suy ra ngày cài đặt thật của họ). Khi phân tích ở tầng report/dashboard: các user này **phải bị loại khỏi mọi phân tích theo cohort/retention/days_since_install** (tự động xảy ra vì cột đó NULL, và acquisition/installs theo ngày sẽ underestimate version 8.2 vì thiếu first_open), nhưng **vẫn hợp lệ và nên được giữ lại** trong các phép đếm tổng quát không phụ thuộc ngày cài đặt (tổng DAU theo ngày, tổng impression, tổng revenue theo ngày) — loại bỏ hoàn toàn các user này khỏi dashboard sẽ làm underestimate các con số tổng đó.

**→ TODO report — Câu hỏi 2 (khuyến nghị kỹ thuật)**: đưa phát hiện này vào phần trả lời câu hỏi 2 dưới dạng khuyến nghị cho đội kỹ thuật — rà soát lại logic gửi event `first_open` trong SDK ở bản 8.2 (thay đổi giữa 8.1→8.2 là nghi phạm chính); trong lúc chờ fix, cần ghi chú rõ khả năng underestimate số liệu installs/acquisition cho version này khi báo cáo.

**Phát hiện 4b — version 8.2 cũng có uninstall rate cao nhất (không phải data quality issue, là tín hiệu thật)**: khi build KPI "Uninstall Count by app_version" trên PBI, version 8.20 cho số tuyệt đối 58,350 uninstall — cao vượt trội (~17x) so với version đứng thứ 2 (8.70: 3,339), nhìn ban đầu giống outlier. Điều tra:
- **Không phải lỗi join nguồn**: đối chiếu `raw.app_remove.app_version` (version lúc gỡ) với `dim_user.install_app_version` (version lúc cài) của cùng user cho thấy 99.7% (58,192/58,350) trùng khớp — user gỡ app đúng version họ đã cài, không phải do update version trước khi gỡ gây lệch số liệu.
- **Phần lớn là do quy mô**: version 8.20 chiếm **101,968/128,746 user (≈79%)** tổng số cài đặt — số tuyệt đối cao chủ yếu vì đây là version chiếm áp đảo, không phải vì tỷ lệ gỡ bất thường riêng lẻ.
- **Nhưng tỷ lệ uninstall_rate vẫn cao nhất**: 8.20 có uninstall_rate = **57.2%** (58,350/101,968), cao hơn rõ rệt so với hầu hết version khác (dao động 18-59%, đa số quanh 25-40%). Sau khi hiệu chỉnh cho phần user bị mất `first_open` (Phát hiện 4, ước tính +1,978 install thật), rate hiệu chỉnh giảm nhẹ nhưng kết luận không đổi (ảnh hưởng ~1.9%, không đáng kể).

**Kết luận**: đây là **tín hiệu thật (real signal), không phải vấn đề chất lượng dữ liệu**. Version 8.2 vừa (a) có bug tracking khiến mất event `first_open` cho ~2% user của bản này (Phát hiện 4), vừa (b) có tỷ lệ uninstall cao nhất trong các version — 2 phát hiện cùng trỏ về 1 version, củng cố giả thuyết bản 8.2 có vấn đề chất lượng/kỹ thuật cần đội dev rà soát (không loại trừ khả năng liên quan: crash, hiệu năng kém, hoặc chính bug tracking cũng ảnh hưởng đến trải nghiệm).

**→ TODO report — Câu hỏi 2**: gộp chung với khuyến nghị ở Phát hiện 4 — đề xuất đội kỹ thuật ưu tiên rà soát app_version 8.2 (cả tracking lẫn stability/UX), vì đây là version chiếm phần lớn user nhưng có cả 2 vấn đề (thiếu tracking + uninstall rate cao nhất) cùng lúc.

**Phát hiện 5 — `tier = NULL` trong `ad_impression` phần lớn không backfill được, gắn liền với Phát hiện 4**: khi build `mart.fact_ad_impression` (join với `mart.dim_ecpm` theo `tier + ad_format`), 2,336 dòng không match được eCPM do `tier` rỗng ngay tại `raw.ad_impression`. Kiểm tra xem có thể lấy `tier` từ `dim_user` của cùng user đó thay thế không: chỉ **7/2,336 dòng** có `dim_user.tier` khác NULL; **2,329 dòng còn lại** thuộc về user cũng không có record trong `dim_user` — trùng với nhóm left-censored ở Phát hiện 4 (cài app trước 01/06/2023, không có `first_open`, nên không có `tier` ở bất kỳ đâu để tra cứu).
**Cách xử lý**: sửa `dwh.fact_ad_impression` dùng `COALESCE(NULLIF(a.tier,''), u.tier)` — backfill được 7 dòng từ `dim_user`. 2,329 dòng còn lại (~0.24% tổng ad_impression) giữ nguyên `tier = NULL`, sẽ tự động bị loại khi `mart.fact_ad_impression` join với `dim_ecpm` (không match được), nên **không tính vào bất kỳ số liệu doanh thu/eCPM/LTV nào** — không có cách nào xác định tier thật của các dòng này nên đây là lựa chọn đúng thay vì đoán/gán tier mặc định.

---
