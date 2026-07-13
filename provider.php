<?php
// โหลด Security Configuration และเริ่มต้น Session
require_once __DIR__ . '/security_config.php';

// ไฟล์นี้ทำหน้าที่เป็น alias/wrapper สำหรับ providerid_api.php 
// เพื่อรองรับ redirect_uri ดั้งเดิมที่ลงทะเบียนไว้กับ MOPH ID (provider.php)
// โดยจะโหลดการทำงานทั้งหมดของ providerid_api.php มาทำงานแทน
require_once __DIR__ . '/providerid_api.php';
