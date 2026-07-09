# Azure SOCKS5 Proxy Tool

Tool tạo SOCKS5 proxy tự động trên Microsoft Azure bằng **Azure Cloud Shell**.

Tool này sẽ tự động:

* Đăng ký Resource Provider cần thiết.
* Tạo Resource Group.
* Tạo VM Ubuntu.
* Mở port proxy trong NSG Azure.
* Mở port trong firewall của VPS.
* Cài và cấu hình `3proxy`.
* Xuất proxy ra file `proxies.txt`.
* Test proxy sau khi tạo.
* Hỗ trợ tạo thêm proxy.
* Hỗ trợ fix proxy lỗi.
* Hỗ trợ xoá từng proxy hoặc xoá toàn bộ Resource Group.

---

## 1. Cấu hình mặc định

```text
Resource Group: azure-proxy-rg
Region: japanwest
VM Name Prefix: proxy-jpw
VM Size: Standard_B2ts_v2
Proxy Username: japan
Proxy Password: japn
Proxy Port: 1080
Admin Username VPS: ubuntu
Image: Ubuntu2204
```

Proxy sau khi tạo sẽ có dạng:

```text
IP:1080:japan:japn
```

Ví dụ:

```text
40.74.xx.xxx:1080:japan:japn
```

---

## 2. Cách chạy nhanh trong Azure Cloud Shell

Vào:

```text
https://portal.azure.com/
```

Mở:

```text
Cloud Shell → Bash
```

Sau đó chạy:

```bash
wget -O azure_proxy_bootstrap.sh https://raw.githubusercontent.com/Solsticen/azure-proxy-tool/refs/heads/main/azure_proxy_bootstrap.sh
chmod +x azure_proxy_bootstrap.sh
bash azure_proxy_bootstrap.sh
```

Tool sẽ hỏi:

```text
Proxy Quantity:
```

Nhập số lượng proxy muốn tạo, ví dụ:

```text
1
```

hoặc:

```text
3
```

Sau khi tạo xong, proxy sẽ nằm trong file:

```bash
~/azure-proxy-tool/proxies.txt
```

Xem danh sách proxy:

```bash
cat ~/azure-proxy-tool/proxies.txt
```

---

## 3. Cấu trúc script được tạo

Sau khi chạy bootstrap, tool sẽ tạo thư mục:

```bash
~/azure-proxy-tool
```

Bên trong có các file:

```text
00_config.sh
01_register_providers.sh
02_make_cloud_init.sh
03_create_proxies.sh
04_test_proxies.sh
05_fix_one_proxy.sh
06_delete_one_proxy.sh
07_delete_all_proxy_rg.sh
08_debug_one_proxy.sh
run.sh
proxies.txt
cloud-init-proxy.yml
```

Ý nghĩa từng file:

```text
00_config.sh              File cấu hình chính
01_register_providers.sh  Đăng ký Resource Provider cần thiết
02_make_cloud_init.sh     Tạo cloud-init để cài 3proxy
03_create_proxies.sh      Tạo proxy mới
04_test_proxies.sh        Test danh sách proxy
05_fix_one_proxy.sh       Fix 3proxy trên VM nếu proxy không chạy
06_delete_one_proxy.sh    Xoá một VM proxy
07_delete_all_proxy_rg.sh Xoá toàn bộ Resource Group
08_debug_one_proxy.sh     Debug trạng thái VM/proxy
run.sh                    Chạy flow chính
```

---

## 4. Cách tạo thêm proxy sau lần đầu

Nếu đã chạy lần đầu và tạo được `proxy-jpw-001`, muốn tạo thêm proxy thì không cần chạy lại bootstrap.

Chạy:

```bash
cd ~/azure-proxy-tool
bash 03_create_proxies.sh 1
```

Tạo thêm 3 proxy:

```bash
cd ~/azure-proxy-tool
bash 03_create_proxies.sh 3
```

Tool sẽ tự đặt tên tiếp theo:

```text
proxy-jpw-002
proxy-jpw-003
proxy-jpw-004
```

Danh sách proxy vẫn được ghi tiếp vào:

```bash
~/azure-proxy-tool/proxies.txt
```

---

## 5. Cách test proxy

Test toàn bộ proxy trong file `proxies.txt`:

```bash
cd ~/azure-proxy-tool
bash 04_test_proxies.sh
```

Test thủ công một proxy:

```bash
curl --socks5-hostname japan:japn@IP_PROXY:1080 https://api.ipify.org
```

Ví dụ:

```bash
curl --socks5-hostname japan:japn@40.74.xx.xxx:1080 https://api.ipify.org
```

Nếu kết quả trả về đúng IP proxy, ví dụ:

```text
40.74.xx.xxx
```

thì proxy hoạt động.

---

## 6. Cách fix proxy nếu VM tạo xong nhưng không kết nối được

Nếu proxy không kết nối được, thường là do `3proxy` trong VPS chưa cài xong hoặc service chưa chạy.

Fix một VM cụ thể:

```bash
cd ~/azure-proxy-tool
bash 05_fix_one_proxy.sh proxy-jpw-001
```

Sau đó test lại:

```bash
bash 04_test_proxies.sh
```

---

## 7. Cách debug proxy

Debug VM cụ thể:

```bash
cd ~/azure-proxy-tool
bash 08_debug_one_proxy.sh proxy-jpw-001
```

Script debug sẽ kiểm tra:

* Trạng thái cloud-init.
* Log cài đặt 3proxy.
* Trạng thái service 3proxy.
* Port đang listen.
* Firewall UFW.
* File cấu hình 3proxy.

Nếu proxy chạy đúng, trong output cần thấy:

```text
Active: active (running)
```

và:

```text
0.0.0.0:1080
```

---

## 8. Cách xoá một proxy

Xoá một VM proxy cụ thể:

```bash
cd ~/azure-proxy-tool
bash 06_delete_one_proxy.sh proxy-jpw-001
```

Tool sẽ yêu cầu xác nhận:

```text
Type DELETE to confirm:
```

Gõ:

```text
DELETE
```

Script sẽ xoá:

* VM.
* NIC.
* Public IP.
* NSG.
* OS Disk.

---

## 9. Cách xoá toàn bộ proxy để tránh tốn tiền

Nếu muốn xoá toàn bộ Resource Group `azure-proxy-rg`:

```bash
cd ~/azure-proxy-tool
bash 07_delete_all_proxy_rg.sh
```

Tool sẽ yêu cầu xác nhận:

```text
Type DELETE to confirm:
```

Gõ:

```text
DELETE
```

Lệnh này sẽ xoá toàn bộ tài nguyên trong Resource Group:

```text
azure-proxy-rg
```

Bao gồm:

* Tất cả VM.
* Public IP.
* Disk.
* NIC.
* NSG.
* VNet nếu có.
* Các tài nguyên liên quan.

Nên xoá khi không dùng để tránh bị tính phí.

---

## 10. Cách sửa cấu hình cơ bản

Mở file cấu hình:

```bash
nano ~/azure-proxy-tool/00_config.sh
```

Nội dung mặc định:

```bash
RESOURCE_GROUP="azure-proxy-rg"
REGION="japanwest"
VM_PREFIX="proxy-jpw"
VM_SIZE="Standard_B2ts_v2"

PROXY_USER="japan"
PROXY_PASS="japn"
PROXY_PORT="1080"

ADMIN_USER="ubuntu"
IMAGE="Ubuntu2204"

EXPORT_FILE="proxies.txt"
CLOUD_INIT_FILE="cloud-init-proxy.yml"

SOURCE_IP="*"
```

Sau khi sửa, lưu lại:

```text
Ctrl + O → Enter → Ctrl + X
```

---

## 11. Đổi region

Mặc định:

```bash
REGION="japanwest"
```

Muốn đổi sang Japan East:

```bash
REGION="japaneast"
```

Nếu đổi region, nên đổi luôn prefix VM để dễ phân biệt:

```bash
VM_PREFIX="proxy-jpe"
```

Sau đó tạo proxy mới:

```bash
cd ~/azure-proxy-tool
bash 02_make_cloud_init.sh
bash 03_create_proxies.sh 1
```

---

## 12. Đổi VM size

Mặc định:

```bash
VM_SIZE="Standard_B2ts_v2"
```

Có thể đổi thành size khác, ví dụ:

```bash
VM_SIZE="Standard_B1s"
```

hoặc:

```bash
VM_SIZE="Standard_B1ms"
```

Sau đó tạo proxy mới:

```bash
cd ~/azure-proxy-tool
bash 03_create_proxies.sh 1
```

Lưu ý: không phải region nào cũng có đủ mọi VM size. Nếu tạo lỗi, thử đổi size hoặc region.

---

## 13. Đổi username/password proxy

Mặc định:

```bash
PROXY_USER="japan"
PROXY_PASS="japn"
```

Ví dụ muốn đổi thành:

```bash
PROXY_USER="proxy"
PROXY_PASS="myStrongPass123"
```

Sau khi sửa `00_config.sh`, cần tạo lại cloud-init:

```bash
cd ~/azure-proxy-tool
bash 02_make_cloud_init.sh
```

Rồi tạo proxy mới:

```bash
bash 03_create_proxies.sh 1
```

Lưu ý: đổi username/password trong `00_config.sh` chỉ áp dụng cho proxy tạo sau đó. Proxy cũ không tự đổi.

Nếu muốn đổi proxy cũ, chạy fix lại VM:

```bash
bash 05_fix_one_proxy.sh proxy-jpw-001
```

---

## 14. Đổi port proxy

Mặc định:

```bash
PROXY_PORT="1080"
```

Có thể đổi thành port khác, ví dụ:

```bash
PROXY_PORT="8888"
```

Sau khi đổi port:

```bash
cd ~/azure-proxy-tool
bash 02_make_cloud_init.sh
bash 03_create_proxies.sh 1
```

Script sẽ:

* Cài 3proxy listen port mới.
* Mở port trong firewall VPS.
* Mở port trong Azure NSG.

---

## 15. Giới hạn IP được phép truy cập proxy

Mặc định script mở proxy cho toàn Internet:

```bash
SOURCE_IP="*"
```

An toàn hơn là chỉ cho IP public của mày truy cập.

Ví dụ IP public của mày là:

```text
1.2.3.4
```

Sửa thành:

```bash
SOURCE_IP="1.2.3.4/32"
```

Sau đó tạo proxy mới:

```bash
cd ~/azure-proxy-tool
bash 03_create_proxies.sh 1
```

Nếu proxy cũ đã tạo trước đó, cần sửa rule NSG thủ công hoặc xoá tạo lại.

---

## 16. Kiểm tra NSG đã mở port chưa

Xem rule NSG của VM:

```bash
az network nsg rule list \
  -g azure-proxy-rg \
  --nsg-name proxy-jpw-001NSG \
  -o table
```

Cần thấy rule dạng:

```text
Allow-SOCKS5-1080
Inbound
Allow
Tcp
1080
```

Mở lại port 1080 nếu cần:

```bash
az network nsg rule create \
  --resource-group azure-proxy-rg \
  --nsg-name proxy-jpw-001NSG \
  --name Allow-SOCKS5-1080 \
  --priority 300 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 1080
```

---

## 17. Xem danh sách VM đã tạo

```bash
az vm list \
  -g azure-proxy-rg \
  -d \
  -o table
```

Xem riêng VM:

```bash
az vm show \
  -g azure-proxy-rg \
  -n proxy-jpw-001 \
  -d \
  -o table
```

---

## 18. Xem IP public của VM

```bash
az vm show \
  -g azure-proxy-rg \
  -n proxy-jpw-001 \
  -d \
  --query publicIps \
  -o tsv
```

---

## 19. Kiểm tra service 3proxy bên trong VPS

Không cần SSH, dùng Azure Run Command:

```bash
az vm run-command invoke \
  -g azure-proxy-rg \
  -n proxy-jpw-001 \
  --command-id RunShellScript \
  --scripts 'systemctl status 3proxy --no-pager; ss -lntp | grep 1080'
```

Nếu đúng, sẽ thấy:

```text
Active: active (running)
```

và:

```text
0.0.0.0:1080
```

---

## 20. File proxy export

Proxy được lưu tại:

```bash
~/azure-proxy-tool/proxies.txt
```

Xem file:

```bash
cat ~/azure-proxy-tool/proxies.txt
```

Format:

```text
ip:port:user:pass
```

Ví dụ:

```text
40.74.xx.xxx:1080:japan:japn
```

Nếu muốn tải về máy, trong Cloud Shell có thể dùng nút upload/download file của giao diện Azure Cloud Shell.

---

## 21. Cập nhật script từ GitHub

Nếu đã sửa file trên GitHub và muốn lấy bản mới nhất:

```bash
rm -rf ~/azure-proxy-tool
wget -O azure_proxy_bootstrap.sh https://raw.githubusercontent.com/Solsticen/azure-proxy-tool/refs/heads/main/azure_proxy_bootstrap.sh
chmod +x azure_proxy_bootstrap.sh
bash azure_proxy_bootstrap.sh
```

Lưu ý: lệnh này xoá thư mục tool local trong Cloud Shell và tải lại script mới. Tài nguyên Azure đã tạo như VM, IP, Resource Group không bị xoá.

---

## 22. Các lỗi thường gặp

### Lỗi 1: Proxy tạo xong nhưng không kết nối được

Kiểm tra:

```bash
cd ~/azure-proxy-tool
bash 08_debug_one_proxy.sh proxy-jpw-001
```

Fix:

```bash
bash 05_fix_one_proxy.sh proxy-jpw-001
```

Test lại:

```bash
bash 04_test_proxies.sh
```

### Lỗi 2: `Could not connect to server`

Thường do:

* 3proxy chưa chạy.
* Port 1080 chưa listen trong VPS.
* Firewall VPS chặn.
* NSG Azure chưa mở port.

Fix nhanh:

```bash
cd ~/azure-proxy-tool
bash 05_fix_one_proxy.sh proxy-jpw-001
```

### Lỗi 3: VM size không khả dụng

Đổi size trong:

```bash
nano ~/azure-proxy-tool/00_config.sh
```

Ví dụ:

```bash
VM_SIZE="Standard_B1s"
```

Rồi tạo lại:

```bash
bash 03_create_proxies.sh 1
```

### Lỗi 4: Hết quota Azure for Students

Thử:

* Đổi region.
* Đổi VM size nhỏ hơn.
* Xoá VM cũ không dùng.
* Kiểm tra quota trong Azure Portal.

Xem VM đang có:

```bash
az vm list -g azure-proxy-rg -d -o table
```

Xoá VM không dùng:

```bash
cd ~/azure-proxy-tool
bash 06_delete_one_proxy.sh proxy-jpw-001
```

---

## 23. Bảo mật

Không nên để proxy mở công khai lâu dài.

Mặc định:

```bash
SOURCE_IP="*"
```

nghĩa là mọi IP trên Internet đều có thể thử kết nối vào port proxy. Dù proxy có username/password, vẫn nên giới hạn IP truy cập nếu có thể.

Nên đổi password proxy mạnh hơn:

```bash
PROXY_PASS="MatKhauManhHon123"
```

Không commit các thông tin nhạy cảm lên GitHub:

* Azure password.
* Client secret.
* SSH private key.
* Token cá nhân.
* File chứa credentials riêng.

---

## 24. Chi phí

VM, OS Disk, Public IP và network resource có thể phát sinh phí.

Khi không dùng nữa, xoá toàn bộ Resource Group:

```bash
cd ~/azure-proxy-tool
bash 07_delete_all_proxy_rg.sh
```

Kiểm tra còn VM không:

```bash
az vm list -g azure-proxy-rg -d -o table
```

---

## 25. Lệnh thường dùng

Tải và chạy tool:

```bash
wget -O azure_proxy_bootstrap.sh https://raw.githubusercontent.com/Solsticen/azure-proxy-tool/refs/heads/main/azure_proxy_bootstrap.sh
chmod +x azure_proxy_bootstrap.sh
bash azure_proxy_bootstrap.sh
```

Tạo thêm 1 proxy:

```bash
```

Tạo thêm 3 proxy:

```bash
cd ~/azure-proxy-tool
bash 03_create_proxies.sh 3
```

Xem proxy:

```bash
cat ~/azure-proxy-tool/proxies.txt
```

Test proxy:

```bash
cd ~/azure-proxy-tool
bash 04_test_proxies.sh
```

Fix proxy:

```bash
cd ~/azure-proxy-tool
bash 05_fix_one_proxy.sh proxy-jpw-001
```

Debug proxy:

```bash
cd ~/azure-proxy-tool
bash 08_debug_one_proxy.sh proxy-jpw-001
```

Xoá một proxy:

```bash
cd ~/azure-proxy-tool
bash 06_delete_one_proxy.sh proxy-jpw-001
```

Xoá toàn bộ:

```bash
cd ~/azure-proxy-tool
bash 07_delete_all_proxy_rg.sh
```
