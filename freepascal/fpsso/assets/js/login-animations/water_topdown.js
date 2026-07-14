var animation = {
    name: 'สระน้ำมุมมองด้านบน (Top-down Pond)',
    desc: 'วงคลื่นกระจายตัวจากมุมมองด้านบน (เลื่อนเมาส์หรือคลิกเพื่อสร้างคลื่น)',
    icon: 'fas fa-dot-circle'
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
    }
    
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};
    window.ANIMATION_CLICK_HANDLER = window.ANIMATION_CLICK_HANDLER || {};
    window.ANIMATION_HOVER_HANDLER = window.ANIMATION_HOVER_HANDLER || {};
    
    let ripples = [];
    let mouseX = -1000;
    let mouseY = -1000;
    let lastMouseRippleTime = 0;

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
    }

    class Ripple {
        constructor(x, y, strength = 1.0) {
            this.x = x;
            this.y = y;
            this.radius = 0;
            this.strength = strength;
            this.maxRadius = Math.random() * 60 + 80; // 80 to 140
            this.speed = Math.random() * 0.5 + 0.8;   // 0.8 to 1.3
            this.active = true;
        }

        update() {
            this.radius += this.speed;
            if (this.radius > this.maxRadius) {
                this.active = false;
            }
        }

        draw(ctx) {
            if (!this.active) return;
            
            // Non-linear fade out for more natural look
            let progress = this.radius / this.maxRadius;
            let opacity = Math.max(0, (1 - Math.pow(progress, 1.5))) * 0.4 * this.strength; 
            
            // Draw 3 concentric rings for each ripple
            for (let i = 0; i < 3; i++) {
                let r = this.radius - (i * 12);
                if (r > 0) {
                    let ringOpacity = opacity * (1 - (i * 0.3));
                    if (ringOpacity > 0) {
                        ctx.beginPath();
                        ctx.arc(this.x, this.y, r, 0, Math.PI * 2);
                        ctx.strokeStyle = `rgba(255, 255, 255, ${ringOpacity})`;
                        // Line width gets thinner as it expands
                        ctx.lineWidth = Math.max(0.1, 1.5 + (1 - progress) - (i * 0.3));
                        ctx.stroke();
                    }
                }
            }
        }
    }

    function handleMouseMove(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        const rect = canvas.getBoundingClientRect();
        mouseX = e.clientX - rect.left;
        mouseY = e.clientY - rect.top;
        
        let now = Date.now();
        // Create ripple every 120ms when mouse moves
        if (now - lastMouseRippleTime > 120) {
            ripples.push(new Ripple(mouseX, mouseY, 0.7)); // slightly weaker strength for hover
            lastMouseRippleTime = now;
        }
    }

    function handleClick(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        const rect = canvas.getBoundingClientRect();
        let mx = e.clientX - rect.left;
        let my = e.clientY - rect.top;
        // Strong ripple on click
        ripples.push(new Ripple(mx, my, 1.5));
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Randomly add ripples (like rain drops on a pond)
        if (Math.random() < 0.02) {
            ripples.push(new Ripple(Math.random() * canvas.width, Math.random() * canvas.height, Math.random() * 0.5 + 0.3));
        }
        
        for (let i = ripples.length - 1; i >= 0; i--) {
            let r = ripples[i];
            r.update();
            if (!r.active) {
                ripples.splice(i, 1);
            } else {
                r.draw(ctx);
            }
        }
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.ANIMATION_HOVER_HANDLER[canvasId] = handleMouseMove;
    window.ANIMATION_CLICK_HANDLER[canvasId] = handleClick;
    sidebar.addEventListener('mousemove', handleMouseMove);
    sidebar.addEventListener('click', handleClick);

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
