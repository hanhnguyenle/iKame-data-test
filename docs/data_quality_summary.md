# Kiểm tra chất lượng dữ liệu — Sản phẩm X

*Tài liệu này tóm tắt kết quả rà soát chất lượng dữ liệu tracking của sản phẩm X trước khi đưa vào phân tích và dashboard. Mục tiêu: xác nhận số liệu trong dashboard/báo cáo là đáng tin cậy, và nêu rõ những điểm cần lưu ý khi diễn giải số liệu.*

Phạm vi dữ liệu: 7 nguồn sự kiện tracking (cài đặt app, mở phiên sử dụng, mức độ tương tác, sử dụng tính năng, nhắc nhở/thông báo, hiển thị quảng cáo, gỡ cài đặt), giai đoạn 01/06/2023 – 31/07/2023.

---

## Kết luận nhanh

Dữ liệu **nhìn chung đáng tin cậy**. Sau khi rà soát toàn diện, chỉ phát hiện **1 loại vấn đề đáng kể**: một phần nhỏ sự kiện bị **ghi nhận trùng lặp** do lỗi kỹ thuật ở khâu tracking (không phải hành vi người dùng thật). Vấn đề này đã được xác định rõ nguyên nhân và xử lý triệt để trước khi dữ liệu được đưa vào các bảng phân tích. Không phát hiện vấn đề nào khác (dữ liệu thiếu bất thường, sai lệch thời gian, giá trị phân loại bất thường...) ở mức đáng lo ngại.

---

## 1. Vấn đề phát hiện: sự kiện bị ghi nhận trùng lặp

### Bản chất vấn đề

Hai trong số bảy loại sự kiện — **sự kiện cài đặt app (first_open)** và **sự kiện hiển thị quảng cáo (ad_impression)** — có một số dòng dữ liệu bị lặp lại giống hệt nhau, bao gồm cả mốc thời gian ghi nhận chính xác đến từng micro giây. Về mặt kỹ thuật, hai sự kiện thật của người dùng không thể xảy ra ở đúng cùng một thời điểm chính xác đến vậy, nên đây được xác nhận là **lỗi tracking gửi trùng dữ liệu** (thường gặp khi ứng dụng gửi lại sự kiện lúc mất kết nối mạng), không phải người dùng thực hiện hành động 2 lần.

### Mức độ ảnh hưởng

| Loại sự kiện | Tỷ lệ bị trùng | Đánh giá |
|---|---:|---|
| Sự kiện cài đặt app (first_open) | ~5,5% | Trung bình — đã xử lý |
| Sự kiện hiển thị quảng cáo (ad_impression) | ~3,1% | Trung bình — đã xử lý |
| Sự kiện mở phiên sử dụng, mức độ tương tác, sử dụng tính năng, nhắc nhở, gỡ cài đặt | 0% | Không phát hiện vấn đề |

**Tại sao vấn đề này quan trọng**: nếu không xử lý, số liệu về lượt cài đặt mới (installs) và số lượt hiển thị quảng cáo (ad impressions) sẽ bị **đếm cao hơn thực tế**. Điều này ảnh hưởng trực tiếp đến độ chính xác của:
- Số liệu tăng trưởng người dùng mới (installs theo ngày/kênh)
- Ước tính doanh thu quảng cáo và giá trị vòng đời người dùng (LTV) — số liệu dùng để đề xuất chi phí thu hút người dùng (CPI) cho bộ phận User Acquisition

### Cách xử lý

Toàn bộ các dòng bị trùng đã được loại bỏ trước khi đưa vào dữ liệu phân tích chính thức, chỉ giữ lại đúng 1 bản ghi cho mỗi sự kiện thật. Dữ liệu gốc (bao gồm cả các dòng trùng) vẫn được lưu giữ nguyên vẹn riêng biệt để có thể đối chiếu lại bất cứ lúc nào nếu cần.

---

## 2. Phát hiện phụ: một số ít trường hợp vị trí địa lý không nhất quán

Trong quá trình xử lý trùng lặp ở mục 1, phát hiện thêm một nhóm nhỏ người dùng (khoảng 11 người, dưới 0,01% tổng số người dùng) mà cùng một sự kiện cài đặt lại được ghi nhận với **2 vị trí địa lý khác nhau** (ví dụ: quốc gia, thành phố khác nhau) dù chắc chắn là cùng một sự kiện (trùng thời gian đến micro giây).

**Khả năng nguyên nhân**: một số trường hợp cho thấy dấu hiệu người dùng sử dụng VPN/proxy khi cài đặt — hệ thống ghi nhận vị trí theo địa chỉ IP (có thể ở nước ngoài) thay vì vị trí thực tế của thiết bị.

**Xử lý**: với mỗi trường hợp này, hệ thống ưu tiên giữ lại thông tin vị trí chi tiết hơn (có ghi rõ thành phố) thay vì thông tin chỉ xác định được ở mức quốc gia — vì thông tin càng chi tiết thường càng đáng tin cậy hơn.

**Mức độ ảnh hưởng**: không đáng kể (dưới 15 người dùng trên tổng số ~128.700 người dùng), không ảnh hưởng đến kết luận phân tích theo quốc gia/nhóm thị trường (tier).

---

## 3. Các khía cạnh khác đã kiểm tra — không phát hiện vấn đề

Ngoài trùng lặp dữ liệu, quá trình rà soát còn kiểm tra các khía cạnh sau trên toàn bộ 7 nguồn dữ liệu, không phát hiện vấn đề đáng kể:

- **Dữ liệu bị thiếu/trống** ở các trường quan trọng (quốc gia, nhóm thị trường, nguồn cài đặt...)
- **Tính nhất quán giữa các bảng** — người dùng xuất hiện ở các sự kiện khác (sử dụng tính năng, xem quảng cáo...) đều có thể đối chiếu về đúng sự kiện cài đặt gốc của họ
- **Tính hợp lý theo thời gian** — không có sự kiện nào được ghi nhận trước ngày người dùng cài đặt app (điều không thể xảy ra trong thực tế)
- **Phạm vi thời gian dữ liệu** — toàn bộ nằm đúng trong khung 01/06/2023 – 31/07/2023 như kỳ vọng
- **Tính hợp lệ của các giá trị phân loại** — định dạng quảng cáo, loại nhắc nhở, nhóm thị trường... đều nằm trong tập giá trị hợp lệ, không có giá trị lạ

---

## 4. Ý nghĩa đối với người đọc báo cáo

- Các số liệu trong dashboard (lượt cài đặt, lượt hiển thị quảng cáo, doanh thu ước tính...) đã được tính trên **dữ liệu đã làm sạch**, phản ánh đúng hành vi thực tế của người dùng, không bị thổi phồng bởi lỗi tracking.
- Đề xuất chi phí thu hút người dùng (CPI) và các phân tích liên quan đến quảng cáo trong báo cáo này đã tính đến việc loại bỏ dữ liệu trùng lặp — nếu không xử lý bước này, các con số đề xuất sẽ cao hơn thực tế khoảng 3%.
- Quy trình xử lý dữ liệu (từ dữ liệu thô → làm sạch → mô hình phân tích) được lưu vết đầy đủ, có thể truy xuất lại nếu cần kiểm tra hoặc mở rộng phân tích trong tương lai.
