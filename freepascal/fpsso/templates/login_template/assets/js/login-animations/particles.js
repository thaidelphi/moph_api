var animation = {
    name: 'อนุภาคลอย (Floating Particles)',
    desc: 'อนุภาคลอยขึ้นแบบหิมะตก (เลื่อนเมาส์ผ่านหรือคลิกเพื่อระเบิดได้)',
    icon: 'fas fa-snowflake'
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
    // Remove old listeners if exist
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
    
    let particles = [];
    let fragments = [];

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initParticles();
    }

    class Particle {
        constructor(yPos) {
            this.x = Math.random() * canvas.width;
            this.y = yPos !== undefined ? yPos : Math.random() * canvas.height;
            this.size = Math.random() * 4 + 1;
            this.speedY = Math.random() * 1 + 0.2;
            this.opacity = Math.random() * 0.5 + 0.1;
        }
        update() {
            this.y -= this.speedY;
            if (this.y < 0) {
                this.y = canvas.height;
                this.x = Math.random() * canvas.width;
            }
        }
        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(255, 255, 255, ${this.opacity})`;
            ctx.fill();
        }
    }

    class Fragment {
        constructor(x, y, colorOpacity) {
            this.x = x;
            this.y = y;
            this.size = Math.random() * 2 + 0.5;
            this.speedX = (Math.random() - 0.5) * 4;
            this.speedY = (Math.random() - 0.5) * 4;
            this.opacity = colorOpacity || 0.8;
            this.decay = Math.random() * 0.02 + 0.02;
        }
        update() {
            this.x += this.speedX;
            this.y += this.speedY;
            this.opacity -= this.decay;
        }
        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(255, 255, 255, ${this.opacity})`;
            ctx.fill();
        }
    }

    function initParticles() {
        particles = [];
        fragments = [];
        const maxParticles = Math.floor((canvas.width * canvas.height) / 4000) || 50;
        for (let i = 0; i < maxParticles; i++) {
            particles.push(new Particle());
        }
    }
    
    function createExplosion(x, y, opacity) {
        let count = Math.random() * 5 + 5; // 5 to 10 fragments
        for (let i = 0; i < count; i++) {
            fragments.push(new Fragment(x, y, opacity));
        }
    }

    function handleExplode(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;
        
        // Find particles under mouse (allow some margin of error for small particles)
        for (let i = particles.length - 1; i >= 0; i--) {
            let p = particles[i];
            let dx = mouseX - p.x;
            let dy = mouseY - p.y;
            let distance = Math.sqrt(dx * dx + dy * dy);
            
            // Hit box radius = particle size + 15px margin
            if (distance < p.size + 15) {
                createExplosion(p.x, p.y, p.opacity + 0.2);
                particles.splice(i, 1);
                // Create a new particle at bottom to replace the destroyed one
                particles.push(new Particle(canvas.height + Math.random() * 20));
            }
        }
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        for (let i = 0; i < particles.length; i++) {
            particles[i].update();
            particles[i].draw();
        }
        
        for (let i = fragments.length - 1; i >= 0; i--) {
            fragments[i].update();
            if (fragments[i].opacity <= 0) {
                fragments.splice(i, 1);
            } else {
                fragments[i].draw();
            }
        }
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    // Register click and mousemove events
    window.ANIMATION_CLICK_HANDLER[canvasId] = handleExplode;
    window.ANIMATION_HOVER_HANDLER[canvasId] = handleExplode;
    sidebar.addEventListener('click', handleExplode);
    sidebar.addEventListener('mousemove', handleExplode);

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
