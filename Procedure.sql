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
    DECLARE v_player_id INT;

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
    SET v_total_machine_cost = (v_total_seconds * v_price_per_hour) / 3600;

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

    -- 7. Xử lý thanh toán bằng số dư thành viên
    IF payment_method_param = 'Member Balance' THEN
        SELECT PlayerID INTO v_player_id FROM SESSION WHERE SessionID = session_id_param;

        IF v_player_id IS NOT NULL THEN
            -- Trừ tiền từ số dư
            UPDATE PLAYER
            SET Balance = Balance - v_grand_total
            WHERE PlayerID = v_player_id;

            -- Ghi log giao dịch
            INSERT INTO TRANSACTION_LOG (PlayerID, EmployeeID, TransactionType, Amount, Note)
            VALUES (v_player_id, employee_id_param, 'Payment', v_grand_total, CONCAT(N'Thanh toán hóa đơn ', LAST_INSERT_ID()));
        END IF;
    END IF;

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
    SET inactive_period = DATE_SUB(NOW(), INTERVAL 3 MONTH);

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
    IN employee_id INT -- (có thể là NULL)
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

    -- Ghi log
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

-- =================================================================
-- 11. CHỨC NĂNG KIỂM TRA CÒN MÁY (Check available machines)
-- =================================================================
DROP PROCEDURE IF EXISTS CheckAvailableMachines;

DELIMITER //

CREATE PROCEDURE CheckAvailableMachines()
BEGIN
    SELECT
        M.MachineID AS MachineID,
        M.MachineName AS MachineName,
        MT.TypeName AS MachineType
    FROM
        MACHINE M
    JOIN
        MACHINE_TYPE MT ON M.TypeID = MT.TypeID
    WHERE
        M.Status = 'Available'
    ORDER BY
        MachineID;
END //

DELIMITER ;

-- =================================================================
-- 12. CHỨC NĂNG CHO PHÉP NGƯỜI CHƠI KIỂM TRA SỐ DƯ CỦA CHÍNH MÌNH
-- (Check Player Balance)
-- =================================================================
-- Ngoài ra cho phép nhân viên/chủ quán kiểm tra số dư của bất kỳ người chơi nào.
DROP PROCEDURE IF EXISTS CheckPlayerBalance;

DELIMITER //

CREATE PROCEDURE CheckPlayerBalance(
    IN player_id_to_check INT,
    IN caller_id INT,
    IN caller_role VARCHAR(20) -- 'Player', 'Staff', hoặc 'Owner'
)
BEGIN
    -- Kiểm tra quyền truy cập
    IF caller_role = 'Player' AND player_id_to_check != caller_id THEN
        -- Người chơi chỉ được kiểm tra số dư của chính mình
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Người chơi chỉ có thể kiểm tra số dư tài khoản của chính mình.';
    ELSE
        -- Nếu là Staff/Owner hoặc Player kiểm tra chính mình, tiến hành truy vấn
        SELECT
            P.PlayerID,
            P.AccountName,
            P.Balance
        FROM
            PLAYER P
        WHERE
            P.PlayerID = player_id_to_check;
    END IF;
END //

DELIMITER ;


-- =================================================================
-- 13. StartSession (Bắt đầu phiên sử dụng máy)
-- =================================================================
DROP PROCEDURE IF EXISTS StartSession;
DELIMITER //
CREATE PROCEDURE StartSession(
    IN machine_id_param INT,
    IN player_id_param INT, -- NULL nếu là khách vãng lai
    IN employee_id_param INT -- Nhân viên thực hiện
)
proc: BEGIN
    DECLARE v_machine_status ENUM('Available', 'In Use', 'Maintenance');
    DECLARE v_price_per_hour DECIMAL(10, 2);
    DECLARE v_type_id INT;
    DECLARE v_session_id INT;


    SELECT M.Status, MT.PricePerHour, M.TypeID
    INTO v_machine_status, v_price_per_hour, v_type_id
    FROM MACHINE M
    JOIN MACHINE_TYPE MT ON M.TypeID = MT.TypeID
    WHERE M.MachineID = machine_id_param;

    IF v_machine_status IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Lỗi: Máy tính không tồn tại.';
        LEAVE proc;
    END IF;

    IF v_machine_status != 'Available' THEN
		SET @mess = CONCAT('Lỗi: Máy ', machine_id_param, ' đang ở trạng thái ', v_machine_status, '. Không thể bắt đầu phiên.');
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = @mess;
        LEAVE proc;
    END IF;

    -- 2. Bắt đầu phiên
    INSERT INTO SESSION (MachineID, PlayerID, StartTime, PricePerHour, Status)
    VALUES (machine_id_param, player_id_param, NOW(), v_price_per_hour, 'Playing');

    SET v_session_id = LAST_INSERT_ID();

    -- 3. Cập nhật trạng thái máy
    UPDATE MACHINE
    SET Status = 'In Use'
    WHERE MachineID = machine_id_param;

    SELECT CONCAT('Phiên mã ', v_session_id, ' đã được bắt đầu trên máy ', machine_id_param, '. Giá: ', v_price_per_hour, ' VNĐ/giờ.') AS Result, v_session_id AS SessionID;

END //
DELIMITER ;

-- =================================================================
-- 14. EndSession (Kết thúc phiên sử dụng máy)
-- =================================================================
DROP PROCEDURE IF EXISTS EndSession;
DELIMITER //
CREATE PROCEDURE EndSession(
    IN session_id_param INT
)
proc: BEGIN
    DECLARE v_machine_id INT;
    DECLARE v_session_status ENUM('Playing', 'Finished', 'Paused');

    -- 1. Kiểm tra trạng thái phiên
    SELECT MachineID, Status
    INTO v_machine_id, v_session_status
    FROM SESSION
    WHERE SessionID = session_id_param;

    IF v_machine_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Phiên sử dụng không tồn tại.';
        LEAVE proc;
    END IF;

    IF v_session_status != 'Playing' THEN
		SET @mess = CONCAT('Lỗi: Phiên ', session_id_param, ' không ở trạng thái Playing. Trạng thái hiện tại: ', v_session_status);
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = @mess;
        LEAVE proc;
    END IF;

    -- 2. Kết thúc phiên (Đặt EndTime)
    UPDATE SESSION
    SET EndTime = NOW()
    WHERE SessionID = session_id_param;

    -- 3. Cập nhật trạng thái máy thành Available
    UPDATE MACHINE
    SET Status = 'Available'
    WHERE MachineID = v_machine_id;

    SELECT CONCAT('Phiên ', session_id_param, ' đã kết thúc. Máy ', v_machine_id, ' đã được giải phóng. Vui lòng tạo hóa đơn.') AS Result;

END //
DELIMITER ;

-- =================================================================
-- 15. AddProductToSession (Thêm sản phẩm/dịch vụ vào phiên)
-- =================================================================
DROP PROCEDURE IF EXISTS AddProductToSession;
DELIMITER //
CREATE PROCEDURE AddProductToSession(
    IN session_id_param INT,
    IN product_id_param INT,
    IN quantity_param INT
)
proc: BEGIN
    DECLARE v_session_status ENUM('Playing', 'Finished', 'Paused');
    DECLARE v_unit_price DECIMAL(10, 2);
    DECLARE v_stock_quantity INT;

    -- 1. Kiểm tra trạng thái phiên
    SELECT Status
    INTO v_session_status
    FROM SESSION
    WHERE SessionID = session_id_param;

    IF v_session_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Phiên sử dụng không tồn tại.';
        LEAVE proc;
    END IF;

    IF v_session_status != 'Playing' THEN
		SET @mess = CONCAT('Lỗi: Chỉ có thể thêm sản phẩm vào phiên đang chơi. Trạng thái hiện tại: ', v_session_status);
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = @mess;
        LEAVE proc;
    END IF;

    -- 2. Kiểm tra sản phẩm và số lượng tồn kho
    SELECT SalePrice, StockQuantity
    INTO v_unit_price, v_stock_quantity
    FROM PRODUCT
    WHERE ProductID = product_id_param;

    IF v_unit_price IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Sản phẩm không tồn tại.';
        LEAVE proc;
    END IF;

    IF v_stock_quantity < quantity_param THEN
		SET @mess = CONCAT('Lỗi: Số lượng tồn kho không đủ. Tồn kho: ', v_stock_quantity, ', Yêu cầu: ', quantity_param);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @mess;
        LEAVE proc;
    END IF;

    -- 3. Thêm vào SESSION_DETAIL
    INSERT INTO SESSION_DETAIL (SessionID, ProductID, Quantity, UnitPrice)
    VALUES (session_id_param, product_id_param, quantity_param, v_unit_price);

    -- 4. Cập nhật tồn kho
    UPDATE PRODUCT
    SET StockQuantity = StockQuantity - quantity_param
    WHERE ProductID = product_id_param;

    SELECT CONCAT('Đã thêm ', quantity_param, ' sản phẩm ', product_id_param, ' vào phiên ', session_id_param) AS Result;

END //
DELIMITER ;

-- =================================================================
-- 16. GetPlayerHistory (Lịch sử sử dụng và giao dịch của người chơi)
-- =================================================================
DROP PROCEDURE IF EXISTS GetPlayerHistory;
DELIMITER //
CREATE PROCEDURE GetPlayerHistory(
    IN player_id_param INT
)
BEGIN
    -- 1. Lịch sử Phiên sử dụng
    SELECT
        S.SessionID,
        M.MachineName,
        MT.TypeName AS MachineType,
        S.StartTime,
        S.EndTime,
        S.PricePerHour,
        S.Status,
        I.GrandTotal AS InvoiceTotal,
        I.InvoiceDate
    FROM
        SESSION S
    JOIN
        MACHINE M ON S.MachineID = M.MachineID
    JOIN
        MACHINE_TYPE MT ON M.TypeID = MT.TypeID
    LEFT JOIN
        INVOICE I ON S.SessionID = I.SessionID
    WHERE
        S.PlayerID = player_id_param
    ORDER BY
        S.StartTime DESC;

    -- 2. Lịch sử Giao dịch (Nạp/Thanh toán)
    SELECT
        TransactionID,
        TransactionType,
        Amount,
        TransactionDate,
        Note
    FROM
        TRANSACTION_LOG
    WHERE
        PlayerID = player_id_param
    ORDER BY
        TransactionDate DESC;

END //
DELIMITER ;


-- =================================================================
-- 17. THỐNG KÊ SẢN PHẨM ĐƯỢC MUA NHIỀU NHẤT VÀ ÍT NHẤT
-- =================================================================
DROP PROCEDURE IF EXISTS GetTopAndBottomProducts;

DELIMITER //

CREATE PROCEDURE GetTopAndBottomProducts(
    IN type_of_statistic INT, -- 1(nhiểu nhất) 2(ít nhất) 3(chưa mua)
    IN start_date DATETIME,
    IN end_date DATETIME,
    IN top_n INT, -- Số lượng sản phẩm top cần lấy (VD: 5, 10)
    IN product_type_filter ENUM('Food', 'Drink', 'Card', 'Other Service') -- Lọc theo loại sản phẩm
)
BEGIN
    -- Sản phẩm được mua NHIỀU NHẤT
    IF type_of_statistic = 1 THEN
    SELECT 
        'TOP PRODUCTS' AS Category,
        P.ProductID,
        P.ProductName,
        P.ProductType,
        P.SalePrice,
        SUM(SD.Quantity) AS TotalQuantitySold,
        SUM(SD.SubTotal) AS TotalRevenue,
        COUNT(DISTINCT SD.SessionID) AS NumberOfOrders
    FROM 
        SESSION_DETAIL SD
    JOIN 
        PRODUCT P ON SD.ProductID = P.ProductID
    JOIN 
        SESSION S ON SD.SessionID = S.SessionID
    JOIN 
        INVOICE I ON S.SessionID = I.SessionID
    WHERE
        I.Status = 'Paid' 
        AND I.InvoiceDate BETWEEN start_date AND end_date
        AND (P.ProductType = product_type_filter)
    GROUP BY 
        P.ProductID, P.ProductName, P.ProductType, P.SalePrice
    ORDER BY 
        TotalQuantitySold DESC
    LIMIT top_n;

    -- Sản phẩm được mua ÍT NHẤT
    ELSEIF type_of_statistic = 2 THEN
    SELECT 
        'BOTTOM PRODUCTS' AS Category,
        P.ProductID,
        P.ProductName,
        P.ProductType,
        P.SalePrice,
        SUM(SD.Quantity) AS TotalQuantitySold,
        SUM(SD.SubTotal) AS TotalRevenue,
        COUNT(DISTINCT SD.SessionID) AS NumberOfOrders
    FROM 
        SESSION_DETAIL SD
    JOIN 
        PRODUCT P ON SD.ProductID = P.ProductID
    JOIN 
        SESSION S ON SD.SessionID = S.SessionID
    JOIN 
        INVOICE I ON S.SessionID = I.SessionID
    WHERE 
        I.Status = 'Paid' 
        AND I.InvoiceDate BETWEEN start_date AND end_date
        AND (P.ProductType = product_type_filter)
    GROUP BY 
        P.ProductID, P.ProductName, P.ProductType, P.SalePrice
    ORDER BY 
        TotalQuantitySold ASC
    LIMIT top_n;

    -- Sản phẩm CHƯA ĐƯỢC BÁN
    ELSE
    SELECT 
        'UNSOLD PRODUCTS' AS Category,
        P.ProductID,
        P.ProductName,
        P.ProductType,
        P.SalePrice,
        P.StockQuantity,
        0 AS TotalQuantitySold,
        0 AS TotalRevenue,
        0 AS NumberOfOrders
    FROM 
        PRODUCT P
    WHERE 
        (P.ProductType = product_type_filter)
        AND P.ProductID NOT IN (
            SELECT DISTINCT SD.ProductID
            FROM SESSION_DETAIL SD
            JOIN SESSION S ON SD.SessionID = S.SessionID
            JOIN INVOICE I ON S.SessionID = I.SessionID
            WHERE I.Status = 'Paid' 
                AND I.InvoiceDate BETWEEN start_date AND end_date
        )
    ORDER BY 
        P.ProductName
	LIMIT top_n;
    
    END IF;

END //

DELIMITER ;


-- =================================================================
-- 18. Tạo tài khoản cho người chơi
-- =================================================================
DELIMITER //

CREATE PROCEDURE RegisterNewPlayer(
    IN p_FullName VARCHAR(100),
    IN p_PhoneNumber VARCHAR(15),
    IN p_AccountName VARCHAR(50),
    IN p_Password VARCHAR(255)
)
BEGIN
    -- Kiểm tra xem Tên tài khoản đã tồn tại chưa
    IF EXISTS (SELECT 1 FROM PLAYER WHERE AccountName = p_AccountName) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi: Tên tài khoản này đã được sử dụng!';
    END IF;

    -- Kiểm tra xem Số điện thoại đã tồn tại chưa
    IF EXISTS (SELECT 1 FROM PLAYER WHERE PhoneNumber = p_PhoneNumber) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi: Số điện thoại này đã được đăng ký!';
    END IF;

    -- Insert dữ liệu (Balance mặc định là 0, MemberType mặc định Regular)
    INSERT INTO PLAYER (FullName, PhoneNumber, AccountName, Password, Balance, MemberType, RegistrationDate)
    VALUES (p_FullName, p_PhoneNumber, p_AccountName, p_Password, 0, 'Regular', NOW());

    -- Trả về ID vừa tạo để sử dụng nếu cần
    SELECT LAST_INSERT_ID() AS NewPlayerID, 'Tạo tài khoản thành công' AS Message;

END //

DELIMITER ;

-- Trigger dùng để tự động tính subtotal
DELIMITER $$

CREATE TRIGGER trg_session_detail_before_insert
BEFORE INSERT ON SESSION_DETAIL
FOR EACH ROW
BEGIN
    SET NEW.SubTotal = NEW.Quantity * NEW.UnitPrice;
END$$

DELIMITER ;

-- 19. Nạp tiền cho thành viên
DELIMITER //

CREATE PROCEDURE sp_TopUpBalance(
    IN p_PlayerID INT,
    IN p_EmployeeID INT,       -- Ai là người thực hiện nạp tiền
    IN p_Amount DECIMAL(10, 2),
    IN p_Note TEXT
)
BEGIN
    -- Khai báo biến để hứng lỗi (nếu có)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Nếu có lỗi xảy ra, hủy bỏ mọi thay đổi và báo lỗi
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi giao dịch: Không thể nạp tiền.';
    END;

    -- Kiểm tra đầu vào: Số tiền nạp phải lớn hơn 0
    IF p_Amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Số tiền nạp phải lớn hơn 0';
    END IF;

    -- Bắt đầu giao dịch
    START TRANSACTION;

    -- 1. Cập nhật số dư cho người chơi
    UPDATE PLAYER 
    SET Balance = Balance + p_Amount 
    WHERE PlayerID = p_PlayerID;

    -- Kiểm tra xem có người chơi nào được update không (tránh trường hợp ID sai)
    IF ROW_COUNT() = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Không tìm thấy PlayerID này.';
    ELSE
        -- 2. Ghi vào lịch sử giao dịch (Transaction Log)
        INSERT INTO TRANSACTION_LOG (
            PlayerID, 
            EmployeeID, 
            TransactionType, 
            Amount, 
            Note
        )
        VALUES (
            p_PlayerID, 
            p_EmployeeID, 
            'Top-up', -- Loại giao dịch là Nạp tiền
            p_Amount, 
            p_Note
        );
        
        -- Xác nhận giao dịch thành công
        COMMIT;
    END IF;

END //

DELIMITER ;
