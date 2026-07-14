var animation = {
    name: 'ผืนน้ำ (Water Surface)',
    desc: 'คลื่นผืนน้ำซ้อนทับกันอย่างนุ่มนวล (เลื่อนเมาส์เพื่อสร้างคลื่น)',
    icon: 'fas fa-water'
};

(function() {
    const currentScript = document.currentScript;
    const canvasId = (currentScript && currentScript.dataset.canvasId) || window.ANIMATION_CANVAS_ID || 'sidebar-canvas';
    const containerSelector = (currentScript && currentScript.dataset.containerSelector) || window.ANIMATION_CONTAINER_SELECTOR || '.login-sidebar';
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const sidebar = document.querySelector(containerSelector);
    if (!sidebar) return;
    
    // Cleanup old animation
    if (window.ANIMATION_ACTIVE_IDS && window.ANIMATION_ACTIVE_IDS[canvasId]) {
        cancelAnimationFrame(window.ANIMATION_ACTIVE_IDS[canvasId]);
    }
    // Remove old listeners
    if (window.ANIMATION_CLICK_HANDLER && window.ANIMATION_CLICK_HANDLER[canvasId]) {
        canvas.removeEventListener('click', window.ANIMATION_CLICK_HANDLER[canvasId]);
        sidebar.removeEventListener('click', window.ANIMATION_CLICK_HANDLER[canvasId]);
    }
    if (window.ANIMATION_HOVER_HANDLER && window.ANIMATION_HOVER_HANDLER[canvasId]) {
        canvas.removeEventListener('mousemove', window.ANIMATION_HOVER_HANDLER[canvasId]);
        sidebar.removeEventListener('mousemove', window.ANIMATION_HOVER_HANDLER[canvasId]);
        canvas.removeEventListener('mouseleave', window.ANIMATION_HOVER_HANDLER[canvasId]);
        sidebar.removeEventListener('mouseleave', window.ANIMATION_HOVER_HANDLER[canvasId]);
    }
    
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};
    window.ANIMATION_CLICK_HANDLER = window.ANIMATION_CLICK_HANDLER || {};
    window.ANIMATION_HOVER_HANDLER = window.ANIMATION_HOVER_HANDLER || {};
    
    let waves = [];
    let time = 0;
    let mouseX = -1000;
    let mouseY = -1000;

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initWaves();
    }

    class WaterWave {
        constructor(yOffset, amplitude, length, speed, color) {
            this.yOffset = yOffset; // 0.0 to 1.0 fraction of canvas height from bottom
            this.baseAmplitude = amplitude;
            this.length = length;
            this.speed = speed;
            this.color = color;
            this.phase = Math.random() * Math.PI * 2;
        }

        draw(ctx, time) {
            ctx.beginPath();
            
            let baseY = canvas.height - (canvas.height * this.yOffset);
            let startY = baseY + Math.sin(time * this.speed + this.phase) * this.baseAmplitude;
            ctx.moveTo(0, startY);
            
            for (let x = 0; x <= canvas.width; x += 10) {
                let y = baseY + Math.sin(x * this.length + time * this.speed + this.phase) * this.baseAmplitude;
                
                // Add ripple effect near mouse
                let dx = x - mouseX;
                let dy = baseY - mouseY;
                let dist = Math.sqrt(dx*dx + dy*dy);
                
                if (dist < 200 && mouseX > 0) {
                    let ripple = Math.cos(dist * 0.05 - time * 0.1) * (200 - dist) * 0.05;
                    y += ripple;
                }
                
                ctx.lineTo(x, y);
            }
            
            ctx.lineTo(canvas.width, canvas.height);
            ctx.lineTo(0, canvas.height);
            ctx.closePath();
            
            ctx.fillStyle = this.color;
            ctx.fill();
        }
    }

    function initWaves() {
        waves = [];
        // Layers of water: deeper is further back
        waves.push(new WaterWave(0.35, 12, 0.003, 0.015, 'rgba(255, 255, 255, 0.05)'));
        waves.push(new WaterWave(0.25, 16, 0.004, 0.02,  'rgba(255, 255, 255, 0.1)'));
        waves.push(new WaterWave(0.15, 20, 0.005, 0.025, 'rgba(255, 255, 255, 0.15)'));
        waves.push(new WaterWave(0.05, 24, 0.006, 0.03,  'rgba(255, 255, 255, 0.25)'));
    }

    function handleMouseMove(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        const rect = canvas.getBoundingClientRect();
        mouseX = e.clientX - rect.left;
        mouseY = e.clientY - rect.top;
    }

    function handleMouseLeave(e) {
        mouseX = -1000;
        mouseY = -1000;
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        time += 1;
        
        waves.forEach(wave => wave.draw(ctx, time));
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.ANIMATION_HOVER_HANDLER[canvasId] = handleMouseMove;
    sidebar.addEventListener('mousemove', handleMouseMove);
    sidebar.addEventListener('mouseleave', handleMouseLeave);

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
