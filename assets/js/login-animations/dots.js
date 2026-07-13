var animation = {
    name: 'จุดเชื่อมต่อ (Constellation Dots)',
    desc: 'อนุภาคจุดเชื่อมเส้นแบบกลุ่มดาว',
    icon: 'fas fa-project-diagram'
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
    
    let particles = [];
    const mouse = { x: null, y: null };

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initParticles();
    }

    class Particle {
        constructor() {
            this.x = Math.random() * canvas.width;
            this.y = Math.random() * canvas.height;
            this.size = Math.random() * 2 + 1;
            this.vx = (Math.random() - 0.5) * 0.5;
            this.vy = (Math.random() - 0.5) * 0.5;
        }
        update() {
            this.x += this.vx;
            this.y += this.vy;
            if (this.x < 0 || this.x > canvas.width) this.vx = -this.vx;
            if (this.y < 0 || this.y > canvas.height) this.vy = -this.vy;
        }
        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
            ctx.fill();
        }
    }

    function initParticles() {
        particles = [];
        const maxParticles = Math.floor((canvas.width * canvas.height) / 7000) || 35;
        for (let i = 0; i < maxParticles; i++) {
            particles.push(new Particle());
        }
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        for (let i = 0; i < particles.length; i++) {
            particles[i].update();
            particles[i].draw();
            for (let j = i; j < particles.length; j++) {
                const dx = particles[i].x - particles[j].x;
                const dy = particles[i].y - particles[j].y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                if (distance < 120) {
                    ctx.beginPath();
                    ctx.strokeStyle = `rgba(255, 255, 255, ${0.15 - distance/800})`;
                    ctx.lineWidth = 1;
                    ctx.moveTo(particles[i].x, particles[i].y);
                    ctx.lineTo(particles[j].x, particles[j].y);
                    ctx.stroke();
                }
            }
            if (mouse.x != null && mouse.y != null) {
                const dx = particles[i].x - mouse.x;
                const dy = particles[i].y - mouse.y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                if (distance < 150) {
                    ctx.beginPath();
                    ctx.strokeStyle = `rgba(139, 92, 246, ${0.3 - distance/500})`;
                    ctx.lineWidth = 1.5;
                    ctx.moveTo(particles[i].x, particles[i].y);
                    ctx.lineTo(mouse.x, mouse.y);
                    ctx.stroke();
                }
            }
        }
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    sidebar.addEventListener('mousemove', (e) => {
        const rect = sidebar.getBoundingClientRect();
        mouse.x = e.clientX - rect.left;
        mouse.y = e.clientY - rect.top;
    });

    sidebar.addEventListener('mouseleave', () => {
        mouse.x = null;
        mouse.y = null;
    });

    resizeCanvas();
    animate();
})();
