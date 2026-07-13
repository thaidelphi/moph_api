<?php
/**
 * Security Configuration File
 * 
 * ไฟล์นี้ใช้สำหรับตั้งค่าความปลอดภัยระดับพื้นฐานสำหรับ PHP
 * รวมถึงการจัดการ Session แบบปลอดภัยและการจัดการ Error 
 * 
 * ควร require ไฟล์นี้เป็นอันดับแรกสุดในหน้า entry point ต่างๆ ของระบบ
 */

// 1. กำหนดการจัดการ Error อย่างปลอดภัย (ป้องกัน Information Disclosure)
error_reporting(E_ALL); // บันทึกข้อผิดพลาดทั้งหมด
ini_set('display_errors', 0); // ปิดการแสดงผลข้อผิดพลาดบนหน้าเว็บ
ini_set('log_errors', 1); // เปิดการบันทึกข้อผิดพลาดลงไฟล์
ini_set('error_log', __DIR__ . '/error.log'); // กำหนดที่เก็บไฟล์ log ของระบบ

// 2. การตั้งค่าความปลอดภัยสำหรับ Session ก่อนเริ่มต้น
if (session_status() === PHP_SESSION_NONE) {
    // ป้องกันไม่ให้ JavaScript อ่านค่า Cookie ได้ (บรรเทาผลกระทบจาก XSS)
    ini_set('session.cookie_httponly', 1);
    
    // ส่ง Cookie ผ่าน HTTPS เท่านั้น (เปิดใช้หากรันด้วย HTTPS ทั้งระบบ)
    ini_set('session.cookie_secure', 1); 
    
    // ใช้ Cookie สำหรับจัดเก็บ Session ID เพียงอย่างเดียวเท่านั้น (ป้องกัน Session Fixation ผ่าน URL Parameter)
    ini_set('session.use_only_cookies', 1);
    
    // ไม่อนุญาตให้ใช้ Session ID จากผู้ใช้ หาก Session ID นั้นไม่ได้ถูกสร้างโดยเซิร์ฟเวอร์
    ini_set('session.use_strict_mode', 1);
    
    // ตั้งค่าเวลาหมดอายุของ Session Cookie เป็นเวลาที่ปิด Browser (0)
    ini_set('session.cookie_lifetime', 0);
    
    // บังคับให้ Cookie แชร์เฉพาะภายใต้ Domain ที่ระบุ (ช่วยป้องกัน Third-party context)
    ini_set('session.cookie_samesite', 'Lax'); // หรือ 'Strict' ตามความเข้มงวดที่ต้องการ

    // เริ่มต้นใช้งาน Session อย่างปลอดภัย
    session_start();
}
