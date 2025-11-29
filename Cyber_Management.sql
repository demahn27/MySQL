-- =================================================================
-- +++++++++++++++++ HỆ THỐNG QUẢN LÝ QUÁN ĐIỆN TỬ +++++++++++++++++
-- =================================================================

-- 1. Bảng MACHINE_TYPE
CREATE TABLE MACHINE_TYPE (
    TypeID INT PRIMARY KEY AUTO_INCREMENT,
    TypeName NVARCHAR(50) NOT NULL UNIQUE, -- Thường, VIP, Gaming, LiveStream
    PricePerHour DECIMAL(10, 2) NOT NULL, -- Giá tiền mỗi giờ (VNĐ)
    ConfigDescription TEXT
);

-- 2. Bảng MACHINE (Máy tính)
CREATE TABLE MACHINE (
    MachineID INT PRIMARY KEY AUTO_INCREMENT,
    MachineName VARCHAR(50) NOT NULL UNIQUE, -- Normal01, VIP05, ...
    TypeID INT NOT NULL,
    Status ENUM('Available', 'In Use', 'Maintenance') DEFAULT 'Available',
    FOREIGN KEY (TypeID) REFERENCES MACHINE_TYPE(TypeID)
);

-- 3. Bảng PLAYER (Người Chơi/Thành viên)
CREATE TABLE PLAYER (
    PlayerID INT PRIMARY KEY AUTO_INCREMENT,
    FullName NVARCHAR(100) NOT NULL,
    PhoneNumber VARCHAR(15) UNIQUE,
    AccountName VARCHAR(50) NOT NULL UNIQUE,
    Password VARCHAR(255) NOT NULL, -- Có thể hash
    MemberType ENUM('Regular', 'VIP', 'SVIP') DEFAULT 'Regular',
    Balance DECIMAL(10, 2) DEFAULT 0, -- Số dư tài khoản (VNĐ)
    RegistrationDate DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 4. Bảng EMPLOYEE (Nhân Viên)
-- Bảng riêng cho nhân viên, bao gồm cả Chủ Quán (Owner)
CREATE TABLE EMPLOYEE (
    EmployeeID INT PRIMARY KEY AUTO_INCREMENT,
    FullName NVARCHAR(100) NOT NULL,
    PhoneNumber VARCHAR(15) UNIQUE,
    Email VARCHAR(100),
    Role ENUM('Owner', 'Staff') NOT NULL, -- Chủ Quán, Nhân viên
    Salary DECIMAL(10, 2),
    HireDate DATE,
    AccountName VARCHAR(50) NOT NULL UNIQUE,
    Password VARCHAR(255) NOT NULL, -- Có thể hash
    Status ENUM('Working', 'Quit') DEFAULT 'Working'
);

-- =================================================================
-- NGHIỆP VỤ (BUSINESS LOGIC)
-- =================================================================

-- 5. Bảng PRODUCT (Sản phẩm/Dịch vụ bán kèm)
CREATE TABLE PRODUCT (
    ProductID INT PRIMARY KEY AUTO_INCREMENT,
    ProductName NVARCHAR(100) NOT NULL,
    ProductType ENUM('Food', 'Drink', 'Card', 'Other Service') NOT NULL,
    SalePrice DECIMAL(10, 2) NOT NULL, -- Giá
    StockQuantity INT DEFAULT 0 -- Số lượng còn lại
);

-- 6. Bảng SESSION (Phiên sử dụng máy)
CREATE TABLE SESSION (
    SessionID INT PRIMARY KEY AUTO_INCREMENT,
    MachineID INT NOT NULL,
    PlayerID INT NULL, -- NULL nếu là khách không tạo tài khoản
    StartTime DATETIME NOT NULL,
    EndTime DATETIME NULL,
    PricePerHour DECIMAL(10, 2) NOT NULL, -- Giá giờ tại thời điểm bắt đầu phiên
    Status ENUM('Playing', 'Finished', 'Paused') DEFAULT 'Playing',
    FOREIGN KEY (MachineID) REFERENCES MACHINE(MachineID),
    FOREIGN KEY (PlayerID) REFERENCES PLAYER(PlayerID)
);

-- 7. Bảng SESSION_DETAIL (Chi tiết dịch vụ/sản phẩm gọi trong phiên)
-- Nếu trong phiên sử dụng không mua dịch vụ gì thì sẽ không tạo ra Session Detail
CREATE TABLE SESSION_DETAIL (
    DetailID INT PRIMARY KEY AUTO_INCREMENT,
    SessionID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL,
    SubTotal DECIMAL(10, 2) NOT NULL, -- Quantity * UnitPrice
    FOREIGN KEY (SessionID) REFERENCES SESSION(SessionID),
    FOREIGN KEY (ProductID) REFERENCES PRODUCT(ProductID)
);

-- 8. Bảng INVOICE (Hóa đơn thanh toán)
-- Cập nhật tên bảng.
CREATE TABLE INVOICE (
    InvoiceID INT PRIMARY KEY AUTO_INCREMENT,
    SessionID INT NOT NULL UNIQUE,
    EmployeeID INT NULL, -- Nhân viên lập hóa đơn (FK mới)
    InvoiceDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    TotalMachineCost DECIMAL(10, 2) NOT NULL,
    TotalProductCost DECIMAL(10, 2) NOT NULL,
    GrandTotal DECIMAL(10, 2) NOT NULL,
    PaymentMethod ENUM('Cash', 'Transfer', 'Member Balance') NOT NULL,
    Status ENUM('Paid', 'Cancelled') DEFAULT 'Paid',
    FOREIGN KEY (SessionID) REFERENCES SESSION(SessionID),
    FOREIGN KEY (EmployeeID) REFERENCES EMPLOYEE(EmployeeID)
);

-- 9. Bảng TRANSACTION_LOG (Lịch sử nạp/trừ tiền của thành viên)
-- Cập nhật tên bảng.
CREATE TABLE TRANSACTION_LOG (
    TransactionID INT PRIMARY KEY AUTO_INCREMENT,
    PlayerID INT NOT NULL,
    EmployeeID INT NULL, -- Nhân viên xử lý giao dịch (FK mới)
    TransactionType ENUM('Top-up', 'Payment') NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    TransactionDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    Note TEXT,
    FOREIGN KEY (PlayerID) REFERENCES PLAYER(PlayerID),
    FOREIGN KEY (EmployeeID) REFERENCES EMPLOYEE(EmployeeID)
);

-- =================================================================
-- HỆ THỐNG QUẢN LÝ QUÁN NET - CÁC HÀM CHỨC NĂNG VÀ STORED PROCEDURES (PHIÊN BẢN CẬP NHẬT)
-- =================================================================


-- =================================================================
-- 0. TẠO HÓA ĐƠN VÀ CHỐT PHIÊN (Đảm bảo tính chính xác của TotalProductCost)
-- =================================================================
DROP PROCEDURE IF EXISTS CreateInvoiceForSession;
DELIMITER //
CREATE PROCEDURE CreateInvoiceForSession(
    IN session_id_param INT,
    IN employee_id_param INT,
    IN payment_method_param ENUM('Cash', 'Transfer', 'Member Balance')
)
proc: BEGIN
    DECLARE v_start_time DATETIME;
    DECLARE v_end_time DATETIME;
    DECLARE v_price_per_hour DECIMAL(10, 2);
    DECLARE v_total_seconds INT;
    DECLARE v_total_machine_cost DECIMAL(10, 2);
    DECLARE v_total_product_cost DECIMAL(10, 2);
    DECLARE v_grand_total DECIMAL(10, 2);

    -- 1. Lấy thông tin phiên chơi
    SELECT StartTime, EndTime, PricePerHour
    INTO v_start_time, v_end_time, v_price_per_hour
    FROM SESSION
    WHERE SessionID = session_id_param;

    -- Kiểm tra phiên chơi đã kết thúc chưa
    IF v_end_time IS NULL THEN
        SELECT 'ERROR' AS status, 'Session has not ended. Cannot create invoice.' AS message;
        LEAVE proc;  -- thoát khỏi stored procedure
    END IF;

    -- 2. Tính toán TotalMachineCost
    SET v_total_seconds = TIMESTAMPDIFF(SECOND, v_start_time, v_end_time);
    SET v_total_machine_cost = (v_total_seconds / 3600) * v_price_per_hour;

    -- 3. Tính toán TotalProductCost (Đảm bảo tính đầy đủ từ SESSION_DETAIL)
    SELECT IFNULL(SUM(SubTotal), 0)
    INTO v_total_product_cost
    FROM SESSION_DETAIL
    WHERE SessionID = session_id_param;

    -- 4. Tính GrandTotal
    SET v_grand_total = v_total_machine_cost + v_total_product_cost;

    -- 5. Cập nhật trạng thái SESSION
    UPDATE SESSION
    SET Status = 'Finished'
    WHERE SessionID = session_id_param;

    -- 6. Tạo INVOICE
    INSERT INTO INVOICE (
        SessionID,
        EmployeeID,
        TotalMachineCost,
        TotalProductCost,
        GrandTotal,
        PaymentMethod,
        Status
    )
    VALUES (
        session_id_param,
        employee_id_param,
        v_total_machine_cost,
        v_total_product_cost,
        v_grand_total,
        payment_method_param,
        'Paid'
    );

    SELECT CONCAT('Hóa đơn cho SessionID ', session_id_param, ' đã được tạo thành công. Tổng tiền: ', v_grand_total) AS Result;

END //
DELIMITER ;

-- =================================================================
-- 1. KIỂM TRA DOANH THU (Check Revenue)
-- =================================================================
DROP PROCEDURE IF EXISTS GetRevenueReport;
DELIMITER //
CREATE PROCEDURE GetRevenueReport(
    IN start_date DATETIME,
    IN end_date DATETIME
)
BEGIN
    SELECT
        DATE(InvoiceDate) AS ReportDate,
        SUM(TotalMachineCost) AS TotalMachineRevenue,
        SUM(TotalProductCost) AS TotalProductRevenue,
        SUM(GrandTotal) AS TotalRevenue
    FROM
        INVOICE
    WHERE
        Status = 'Paid' AND InvoiceDate BETWEEN start_date AND end_date
    GROUP BY
        DATE(InvoiceDate)
    ORDER BY
        ReportDate;
END //
DELIMITER ;

-- =================================================================
-- 2. THỐNG KÊ SỐ LƯỢT SỬ DỤNG MÁY (Statistics on Machine Usage Sessions)
-- =================================================================
DROP PROCEDURE IF EXISTS GetMachineUsageStats;
DELIMITER //
CREATE PROCEDURE GetMachineUsageStats(
    IN start_date DATETIME,
    IN end_date DATETIME,
    IN machine_id INT
)
BEGIN
    SELECT
        M.MachineName,
        COUNT(S.SessionID) AS TotalSessions,
        SUM(TIMESTAMPDIFF(SECOND, S.StartTime, S.EndTime)) / 3600 AS TotalHoursUsed -- Tính tổng giờ sử dụng
    FROM
        SESSION S
    JOIN
        MACHINE M ON S.MachineID = M.MachineID
    WHERE
        S.Status = 'Finished'
        AND S.EndTime IS NOT NULL
        AND S.StartTime BETWEEN start_date AND end_date
        AND (machine_id IS NULL OR S.MachineID = machine_id)
    GROUP BY
        M.MachineName
    ORDER BY
        TotalHoursUsed DESC;
END //
DELIMITER ;

-- =================================================================
-- 3. THỐNG KÊ SỐ LƯỢNG NHÂN VIÊN (Statistics on Employee Count)
-- =================================================================
DROP PROCEDURE IF EXISTS GetEmployeeCount;
DELIMITER //
CREATE PROCEDURE GetEmployeeCount()
BEGIN
    SELECT
        Role,
        Status,
        COUNT(EmployeeID) AS EmployeeCount
    FROM
        EMPLOYEE
    GROUP BY
        Role, Status
    ORDER BY
        Role, Status;
END //
DELIMITER ;

-- =================================================================
-- 4. NÂNG CẤP KIỂU THÀNH VIÊN (Upgrade Member Type)
-- =================================================================
DROP PROCEDURE IF EXISTS UpgradeMemberType;
DELIMITER //
CREATE PROCEDURE UpgradeMemberType(
    IN player_id INT
)
BEGIN
    DECLARE total_hours DECIMAL(10, 2);
    DECLARE total_spent DECIMAL(10, 2);
    DECLARE current_type ENUM('Regular', 'VIP', 'SVIP');
    DECLARE new_type ENUM('Regular', 'VIP', 'SVIP');

    -- 1. Lấy thông tin hiện tại
    SELECT MemberType INTO current_type FROM PLAYER WHERE PlayerID = player_id;

    -- 2. Tính tổng giờ chơi (từ các phiên đã kết thúc)
    SELECT
        IFNULL(SUM(TIMESTAMPDIFF(SECOND, StartTime, EndTime)) / 3600, 0)
    INTO
        total_hours
    FROM
        SESSION
    WHERE
        PlayerID = player_id AND Status = 'Finished' AND EndTime IS NOT NULL;

    -- 3. Tính tổng tiền đã chi tiêu (từ các hóa đơn đã thanh toán)
    -- Vẫn dùng INVOICE vì CreateInvoiceForSession đã đảm bảo tính chính xác
    SELECT
        IFNULL(SUM(I.GrandTotal), 0)
    INTO
        total_spent
    FROM
        INVOICE I
    JOIN
        SESSION S ON I.SessionID = S.SessionID
    WHERE
        S.PlayerID = player_id AND I.Status = 'Paid';

    SET new_type = current_type;

    -- Logic nâng cấp
    IF current_type = 'Regular' THEN
        IF total_hours >= 100 OR total_spent >= 1000000 THEN -- Nếu chơi trên 100h hoặc tiêu 1 trịu
            SET new_type = 'VIP';
        END IF;
    ELSEIF current_type = 'VIP' THEN
        IF total_hours >= 500 OR total_spent >= 5000000 THEN -- Nếu chơi trên 500h hoặc tiêu 5 trịu
            SET new_type = 'SVIP';
        END IF;
    END IF;

    -- Cập nhật nếu có thay đổi
    IF new_type <> current_type THEN
        UPDATE PLAYER
        SET MemberType = new_type
        WHERE PlayerID = player_id;
        SELECT CONCAT('Thành viên ', player_id, ' đã được nâng cấp từ ', current_type, ' lên ', new_type) AS Result;
    ELSE
        SELECT CONCAT('Thành viên ', player_id, ' vẫn giữ hạng ', current_type) AS Result;
    END IF;

END //
DELIMITER ;

-- =================================================================
-- 5. HẠ CẤP KIỂU THÀNH VIÊN (Downgrade Member Type)
-- =================================================================
DROP PROCEDURE IF EXISTS DowngradeInactiveMembers;
DELIMITER //
CREATE PROCEDURE DowngradeInactiveMembers()
BEGIN
    DECLARE inactive_period DATE;
    SET inactive_period = DATE_SUB(CURDATE(), INTERVAL 3 MONTH);

    -- Cập nhật thành viên VIP/SVIP không có phiên chơi nào sau ngày inactive_period
    UPDATE PLAYER P
    LEFT JOIN (
        SELECT PlayerID, MAX(StartTime) AS LastSession
        FROM SESSION
        GROUP BY PlayerID
    ) AS LastS ON P.PlayerID = LastS.PlayerID
    SET P.MemberType = 'Regular'
    WHERE
        P.MemberType IN ('VIP', 'SVIP')
        AND (LastS.LastSession IS NULL OR LastS.LastSession < inactive_period);

    SELECT ROW_COUNT() AS DowngradedMembersCount;
END //
DELIMITER ;

-- =================================================================
-- 6. TẶNG THÊM TIỀN KHI MỚI TẠO TÀI KHOẢN (Give Bonus on Account Creation)
-- =================================================================
DROP PROCEDURE IF EXISTS GiveNewAccountBonus;
DELIMITER //
CREATE PROCEDURE GiveNewAccountBonus(
    IN player_id INT,
    IN bonus_amount DECIMAL(10, 2),
    IN employee_id INT -- Nhân viên thực hiện (có thể là NULL nếu hệ thống tự động)
)
BEGIN
    DECLARE is_first_transaction INT;

    -- Kiểm tra xem đây có phải là giao dịch đầu tiên (ngoài giao dịch nạp tiền) không
    SELECT COUNT(*) INTO is_first_transaction
    FROM TRANSACTION_LOG
    WHERE PlayerID = player_id;

    IF is_first_transaction = 0 THEN
        -- Cập nhật số dư
        UPDATE PLAYER
        SET Balance = Balance + bonus_amount
        WHERE PlayerID = player_id;

        -- Ghi log giao dịch
        INSERT INTO TRANSACTION_LOG (PlayerID, EmployeeID, TransactionType, Amount, Note)
        VALUES (player_id, employee_id, 'Top-up', bonus_amount, N'Thưởng tạo tài khoản mới');

        SELECT CONCAT('Đã tặng ', bonus_amount, ' VNĐ cho tài khoản ', player_id) AS Result;
    ELSE
        SELECT CONCAT('Tài khoản ', player_id, ' đã có giao dịch, không thể nhận thưởng tạo tài khoản.') AS Result;
    END IF;
END //
DELIMITER ;

-- =================================================================
-- 7. THỐNG KÊ SỐ LƯỢNG MẶT HÀNG DỊCH VỤ ĐƯỢC BÁN (Statistics on Products Sold)
-- =================================================================
DROP PROCEDURE IF EXISTS GetProductSalesStats;
DELIMITER //
CREATE PROCEDURE GetProductSalesStats(
    IN start_date DATETIME,
    IN end_date DATETIME
)
BEGIN
    SELECT
        P.ProductName,
        P.ProductType,
        SUM(SD.Quantity) AS TotalQuantitySold,
        SUM(SD.SubTotal) AS TotalProductRevenue
    FROM
        SESSION_DETAIL SD
    JOIN
        PRODUCT P ON SD.ProductID = P.ProductID
    JOIN
        SESSION S ON SD.SessionID = S.SessionID
    JOIN
        INVOICE I ON S.SessionID = I.SessionID
    WHERE
        I.Status = 'Paid' AND I.InvoiceDate BETWEEN start_date AND end_date
    GROUP BY
        P.ProductName, P.ProductType
    ORDER BY
        TotalQuantitySold DESC;
END //
DELIMITER ;

-- =================================================================
-- 8. THỐNG KÊ TRẠNG THÁI MÁY (Statistics on Machine Status)
-- =================================================================
DROP PROCEDURE IF EXISTS GetMachineStatusStats;
DELIMITER //
CREATE PROCEDURE GetMachineStatusStats()
BEGIN
    SELECT
        Status,
        COUNT(MachineID) AS MachineCount
    FROM
        MACHINE
    GROUP BY
        Status;
END //
DELIMITER ;

-- =================================================================
-- 9. CHỨC NĂNG KHÓA MÁY (Lock Machine)
-- =================================================================
DROP PROCEDURE IF EXISTS LockMachine;
DELIMITER //
CREATE PROCEDURE LockMachine(
    IN machine_id INT,
    IN reason TEXT
)
BEGIN
    -- Cập nhật trạng thái máy thành 'Maintenance' (Khóa)
    UPDATE MACHINE
    SET Status = 'Maintenance'
    WHERE MachineID = machine_id;

    -- Ghi log (tùy chọn, không có bảng log máy hỏng nên ta chỉ cập nhật trạng thái)
    SELECT CONCAT('Máy ', machine_id, ' đã được khóa với lý do: ', reason) AS Result;
END //
DELIMITER ;

-- =================================================================
-- 10. CHỨC NĂNG MỞ KHÓA MÁY (Unlock Machine)
-- =================================================================
DROP PROCEDURE IF EXISTS UnlockMachine;
DELIMITER //
CREATE PROCEDURE UnlockMachine(
    IN machine_id INT
)
BEGIN
    -- Cập nhật trạng thái máy thành 'Available' (Sẵn sàng)
    UPDATE MACHINE
    SET Status = 'Available'
    WHERE MachineID = machine_id;

    SELECT CONCAT('Máy ', machine_id, ' đã được mở khóa và sẵn sàng sử dụng.') AS Result;
END //
DELIMITER ;
