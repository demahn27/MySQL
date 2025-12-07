CREATE DATABASE CYBER_MANAGEMENT;
USE CYBER_MANAGEMENT;

-- =================================================================
-- +++++++++++++++++ HỆ THỐNG QUẢN LÝ QUÁN ĐIỆN TỬ +++++++++++++++++
-- =================================================================

-- 1. Bảng MACHINE_TYPE
CREATE TABLE MACHINE_TYPE (
    TypeID INT PRIMARY KEY AUTO_INCREMENT,
    TypeName VARCHAR(50) NOT NULL UNIQUE, -- Thường, VIP, Gaming, LiveStream
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
    FullName VARCHAR(100) NOT NULL,
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
    FullName VARCHAR(100) NOT NULL,
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
    ProductName VARCHAR(100) NOT NULL,
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
