from flask import Flask, render_template, request, redirect, url_for
import mysql.connector

app = Flask(__name__)

# --- CẤU HÌNH DATABASE ---
db_config = {
    'host': 'localhost',
    'user': 'root',
    'password': '123',
    'database': 'cyber_management'
}

# --- CẤU HÌNH DANH SÁCH PROCEDURE VÀ INPUT ---
# Định nghĩa tên Procedure và danh sách các tham số (Label hiển thị)
PROCEDURES = {
    # --- NHÓM 1: QUẢN LÝ PHIÊN (SESSION) ---
    'sp_TopUpBalance': {
        'title': 'Nạp tiền tài khoản (Top-up)',
        'params': ['Mã người chơi (Player ID)', 'Mã nhân viên thực hiện', 'Số tiền nạp (VNĐ)', 'Ghi chú giao dịch']
    },
    'StartSession': {
        'title': 'Bắt đầu phiên (Start Session)',
        'params': ['Mã máy (Machine ID)', 'Mã người chơi (Player ID - Để trống nếu khách vãng lai)', 'Mã nhân viên thực hiện']
    },
    'EndSession': {
        'title': 'Kết thúc phiên (End Session)',
        'params': ['Mã phiên (Session ID)']
    },
    'AddProductToSession': {
        'title': 'Gọi đồ ăn/dịch vụ',
        'params': ['Mã phiên (Session ID)', 'Mã sản phẩm (Product ID)', 'Số lượng']
    },
    'CreateInvoiceForSession': {
        'title': 'Tạo hóa đơn & Thanh toán',
        'params': ['Mã phiên (Session ID)', 'Mã nhân viên thu ngân', 'Phương thức (Cash/Transfer/Member Balance)']
    },

    # --- NHÓM 2: QUẢN LÝ MÁY TÍNH ---
    'CheckAvailableMachines': {
        'title': 'Kiểm tra máy trống',
        'params': [] 
    },
    'LockMachine': {
        'title': 'Khóa máy (Bảo trì)',
        'params': ['Mã máy (Machine ID)', 'Lý do khóa']
    },
    'UnlockMachine': {
        'title': 'Mở khóa máy',
        'params': ['Mã máy (Machine ID)']
    },
    'GetMachineStatusStats': {
        'title': 'Thống kê trạng thái dàn máy',
        'params': []
    },
    'GetMachineUsageStats': {
        'title': 'Báo cáo hiệu suất sử dụng máy',
        'params': ['Ngày bắt đầu (YYYY-MM-DD)', 'Ngày kết thúc (YYYY-MM-DD)', 'Mã máy (Để trống nếu xem tất cả)']
    },

    # --- NHÓM 3: QUẢN LÝ THÀNH VIÊN (PLAYER) ---
    'RegisterNewPlayer': {
        'title': 'Đăng ký tài khoản thành viên mới',
        'params': ['Họ tên đầy đủ', 'Số điện thoại', 'Tên tài khoản (AccountName)', 'Mật khẩu']
    },
    'CheckPlayerBalance': {
        'title': 'Kiểm tra số dư tài khoản',
        'params': ['Mã người chơi cần xem', 'Mã người yêu cầu (Caller ID)', 'Vai trò (Player/Staff/Owner)']
    },
    'GetPlayerHistory': {
        'title': 'Lịch sử chơi & Giao dịch',
        'params': ['Mã người chơi (Player ID)']
    },
    'GiveNewAccountBonus': {
        'title': 'Tặng tiền thành viên mới',
        'params': ['Mã người chơi', 'Số tiền thưởng', 'Mã nhân viên thực hiện']
    },
    'UpgradeMemberType': {
        'title': 'Xét nâng hạng thành viên (VIP/SVIP)',
        'params': ['Mã người chơi']
    },
    'DowngradeInactiveMembers': {
        'title': 'Hạ cấp thành viên không hoạt động',
        'params': [] 
    },

    # --- NHÓM 4: BÁO CÁO & THỐNG KÊ ---
    'GetRevenueReport': {
        'title': 'Báo cáo doanh thu ngày',
        'params': ['Ngày bắt đầu (YYYY-MM-DD)', 'Ngày kết thúc (YYYY-MM-DD)']
    },
    'GetProductSalesStats': {
        'title': 'Thống kê doanh số bán hàng',
        'params': ['Ngày bắt đầu (YYYY-MM-DD)', 'Ngày kết thúc (YYYY-MM-DD)']
    },
    'GetTopAndBottomProducts': {
        'title': 'Sản phẩm Bán chạy/Ế/Chưa bán',
        'params': [
            'Loại thống kê (1:Nhiều nhất, 2:Ít nhất, 3:Chưa bán)', 
            'Ngày bắt đầu', 
            'Ngày kết thúc', 
            'Top N (VD: 5, 10)', 
            'Loại SP (Food/Drink/Card/Other Service)'
        ]
    },
    'GetEmployeeCount': {
        'title': 'Thống kê nhân sự',
        'params': []
    }
}

def get_db_connection():
    conn = mysql.connector.connect(**db_config)
    return conn

@app.route('/')
def index():
    return render_template('index.html', procedures=PROCEDURES)

@app.route('/proc/<proc_name>', methods=['GET', 'POST'])
def execute_procedure(proc_name):
    if proc_name not in PROCEDURES:
        return "Procedure not found", 404
    
    proc_info = PROCEDURES[proc_name]
    
    if request.method == 'POST':
        # Lấy dữ liệu từ form
        form_data = []
        for i in range(len(proc_info['params'])):
            val = request.form.get(f'param_{i}')
            # Xử lý input rỗng thành None cho SQL
            if val == '': 
                val = None
            form_data.append(val)
        
        results = []
        messages = []
        error = None
        
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            
            # Gọi Stored Procedure
            cursor.callproc(proc_name, form_data)
            
            # Lấy kết quả trả về (SELECT statements trong procedure)
            for result in cursor.stored_results():
                columns = [col[0] for col in result.description]
                rows = result.fetchall()
                results.append({'columns': columns, 'rows': rows})
                
            conn.commit()
            cursor.close()
            conn.close()
            
            # Nếu không có bảng kết quả nào (chỉ update/insert), thêm thông báo thành công
            if not results:
                messages.append("Thực thi thành công (Không có dữ liệu trả về).")
                
        except mysql.connector.Error as err:
            error = f"Lỗi SQL: {err}"
        except Exception as e:
            error = f"Lỗi hệ thống: {e}"

        return render_template('result.html', 
                               proc_title=proc_info['title'], 
                               results=results, 
                               messages=messages, 
                               error=error)

    return render_template('form.html', proc_name=proc_name, proc_info=proc_info)

@app.route('/source-code')
def view_source_code():
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(buffered=True) 
        
        source_codes = {}
        
        for proc_name in PROCEDURES.keys():
            try:
                check_sql = f"SHOW PROCEDURE STATUS WHERE Name = '{proc_name}'"
                cursor.execute(check_sql)
                exists = cursor.fetchone()
                
                if exists:
                    cursor.execute(f"SHOW CREATE PROCEDURE {proc_name}")
                    result = cursor.fetchone()
                    if result:
                        source_codes[proc_name] = result[2]
                    else:
                        source_codes[proc_name] = "-- Không lấy được nội dung --"
                else:
                     source_codes[proc_name] = f"-- Lỗi: Procedure '{proc_name}' chưa được tạo trong Database --"
                     print(f"Cảnh báo: Không tìm thấy {proc_name} trong MySQL")

            except mysql.connector.Error as err:
                
                print(f"Lỗi SQL tại {proc_name}: {err}")
                source_codes[proc_name] = f"-- Lỗi SQL: {err} --"
        
        cursor.close()
        conn.close()
        return render_template('source_code.html', source_codes=source_codes)

    except Exception as e:
        print(f"Lỗi hệ thống: {e}")
        return f"<h1>Đã xảy ra lỗi hệ thống</h1><p>{e}</p>"

if __name__ == '__main__':
    app.run(debug=True)