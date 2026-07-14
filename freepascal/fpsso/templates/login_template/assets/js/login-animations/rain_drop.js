var animation = {
    name: 'สายฝนโปรยปราย (Rain Drops)',
    desc: 'หยดน้ำฝนตกลงมาระยิบระยับพร้อมเอฟเฟกต์สะท้อนน้ำ',
    icon: 'fas fa-tint'
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
    
    let raindrops = [];
    let splashes = [];
    const wind = -0.6; // Slight slant to the left for realistic wind effect

    class Raindrop {
        constructor(isInitial = false) {
            this.reset(isInitial);
        }

        reset(isInitial = false) {
            this.x = Math.random() * (canvas.width + 100) - 50; // allow starting offscreen left/right
            this.y = isInitial ? Math.random() * canvas.height : -30;
            this.z = Math.random(); // Depth layer: 0 = far, 1 = close
            
            // Map depth to size, speed, and opacity (3D parallax effect)
            this.length = 8 + this.z * 18;  // 8px to 26px
            this.speed = 10 + this.z * 12; // 10px to 22px
            this.weight = 0.8 + this.z * 1.6; // 0.8px to 2.4px thickness
            
            const alpha = 0.12 + this.z * 0.38; // 0.12 to 0.50 opacity
            // Premium light ice-blue/cyan glow color palette
            this.color = `rgba(186, 224, 255, ${alpha})`;
        }

        update() {
            this.y += this.speed;
            this.x += wind;

            // Check if raindrop hit the bottom of the canvas
            if (this.y > canvas.height) {
                // Spawn splash particles if foreground/midground
                if (this.z > 0.3 && Math.random() < 0.6) {
                    createSplash(this.x, canvas.height, this.z);
                }
                this.reset();
            }

            // Recycle if off canvas boundaries
            if (this.x < -30) {
                this.x = canvas.width + 20;
            } else if (this.x > canvas.width + 30) {
                this.x = -20;
            }
        }

        draw() {
            ctx.beginPath();
            ctx.strokeStyle = this.color;
            ctx.lineWidth = this.weight;
            ctx.lineCap = 'round';
            ctx.moveTo(this.x, this.y);
            // Slanted drop path based on wind and length
            ctx.lineTo(this.x + wind * (this.length / this.speed), this.y + this.length);
            ctx.stroke();
        }
    }

    class Splash {
        constructor(x, y, z) {
            this.x = x;
            this.y = y;
            // Splash particles bounce up and out
            this.vx = (Math.random() - 0.5) * 3;
            this.vy = -(Math.random() * 2.5 + 0.8);
            this.gravity = 0.18;
            this.size = 0.6 + z * 1.2;
            const alpha = 0.3 + z * 0.5;
            this.color = `rgba(186, 224, 255, ${alpha})`;
            this.life = 1.0;
            this.decay = 0.04 + Math.random() * 0.05;
        }

        update() {
            this.x += this.vx;
            this.y += this.vy;
            this.vy += this.gravity;
            this.life -= this.decay;
        }

        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = this.color;
            ctx.globalAlpha = this.life;
            ctx.fill();
            ctx.globalAlpha = 1.0;
        }
    }

    function createSplash(x, y, z) {
        if (splashes.length > 80) return; // Prevent performance drops
        const count = Math.floor(Math.random() * 3) + 2; // 2 to 4 splash particles
        for (let i = 0; i < count; i++) {
            splashes.push(new Splash(x, y, z));
        }
    }

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initRain();
    }

    function initRain() {
        raindrops = [];
        splashes = [];
        // Determine raindrop density based on canvas area
        const count = Math.floor((canvas.width * canvas.height) / 7000) || 35;
        const cappedCount = Math.min(count, 120); // Cap to preserve mobile device performance
        for (let i = 0; i < cappedCount; i++) {
            raindrops.push(new Raindrop(true));
        }
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Update & Draw Raindrops
        for (let i = 0; i < raindrops.length; i++) {
            raindrops[i].update();
            raindrops[i].draw();
        }

        // Update & Draw Splashes
        for (let i = splashes.length - 1; i >= 0; i--) {
            splashes[i].update();
            if (splashes[i].life <= 0) {
                splashes.splice(i, 1);
            } else {
                splashes[i].draw();
            }
        }

        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
