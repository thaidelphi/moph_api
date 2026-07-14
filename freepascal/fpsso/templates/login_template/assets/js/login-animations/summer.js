var animation = {
    name: 'ฤดูร้อน (Summer Vibes)',
    desc: 'ละอองแสงแดดและไอความร้อนลอยขึ้น',
    icon: 'fas fa-sun'
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
    
    // Cleanup old animation if any
    if (window.ANIMATION_ACTIVE_IDS && window.ANIMATION_ACTIVE_IDS[canvasId]) {
        cancelAnimationFrame(window.ANIMATION_ACTIVE_IDS[canvasId]);
    }
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};

    let width, height;
    let particles = [];

    class Particle {
        constructor() {
            this.reset();
            this.y = Math.random() * height; // initial random vertical position
        }
        reset() {
            this.x = Math.random() * width;
            this.y = height + Math.random() * 100; // start slightly below screen
            this.size = Math.random() * 3 + 1; // 1 to 4 radius
            this.speedY = Math.random() * 1.5 + 0.5; // upward speed
            this.speedX = (Math.random() - 0.5) * 0.8; // horizontal drift
            this.opacity = Math.random() * 0.6 + 0.2;
            
            // Warm colors: Yellow, Orange, Light Peach, White
            const colors = ['253, 224, 71', '251, 146, 60', '255, 237, 213', '255, 255, 255'];
            this.color = colors[Math.floor(Math.random() * colors.length)];
            this.wobbleSpeed = Math.random() * 0.05 + 0.02;
            this.wobbleFactor = Math.random() * 0.5 + 0.2;
            this.wobbleOffset = Math.random() * Math.PI * 2;
        }
        update() {
            this.y -= this.speedY;
            this.x += this.speedX;
            // sinusoidal wobble for organic movement
            this.x += Math.sin(this.y * this.wobbleSpeed + this.wobbleOffset) * this.wobbleFactor;

            // slightly fade out near top
            if (this.y < height * 0.2) {
                this.opacity -= 0.01;
            }

            if (this.y < -20 || this.opacity <= 0 || this.x < -20 || this.x > width + 20) {
                this.reset();
            }
        }
        draw(ctx) {
            if (this.opacity <= 0) return;
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(${this.color}, ${Math.max(0, this.opacity)})`;
            ctx.shadowBlur = this.size * 3;
            ctx.shadowColor = `rgba(${this.color}, ${Math.max(0, this.opacity * 0.8)})`;
            ctx.fill();
            ctx.shadowBlur = 0; // reset shadow for next draw
        }
    }

    function resizeCanvas() {
        width = canvas.width = sidebar.clientWidth;
        height = canvas.height = sidebar.clientHeight;
        
        // Calculate particle density based on area
        const area = width * height;
        const particleCount = Math.min(150, Math.floor(area / 6000));
        
        particles = [];
        for(let i = 0; i < particleCount; i++) {
            particles.push(new Particle());
        }
    }

    function animate() {
        ctx.clearRect(0, 0, width, height);
        
        for(let i = 0; i < particles.length; i++) {
            particles[i].update();
            particles[i].draw(ctx);
        }
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
