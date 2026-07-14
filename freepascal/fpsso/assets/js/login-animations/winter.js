var animation = {
    name: 'หิมะโปรยปราย (Winter Snowfall)',
    desc: 'เกล็ดหิมะตกลงมาอย่างช้าๆ พริ้วไหว สวยงามและสบายตา',
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
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};
    
    let snowflakes = [];
    let time = 0;

    class Snowflake {
        constructor(isInitial = false) {
            this.reset(isInitial);
        }

        reset(isInitial = false) {
            this.x = Math.random() * canvas.width;
            this.y = isInitial ? Math.random() * canvas.height : -20;
            this.z = Math.random(); // Depth layer: 0 = background (far), 1 = foreground (close)
            
            // Map depth to size, speed, and opacity (3D parallax effect)
            this.size = 1.2 + this.z * 5.0; // 1.2px to 6.2px
            this.speedY = 0.5 + this.z * 1.5; // 0.5px to 2.0px per frame
            
            // Swing effect (drifting back and forth)
            this.swingAngle = Math.random() * Math.PI * 2;
            this.swingSpeed = 0.01 + Math.random() * 0.02;
            this.swingRange = 0.2 + this.z * 0.8; // far flakes swing less
            
            // Rotation for detailed foreground flakes
            this.rotation = Math.random() * Math.PI * 2;
            this.rotationSpeed = (Math.random() - 0.5) * 0.015;
            
            const alpha = 0.15 + this.z * 0.65; // 0.15 to 0.80 opacity
            this.color = `rgba(255, 255, 255, ${alpha})`;
        }

        update(wind) {
            this.y += this.speedY;
            this.swingAngle += this.swingSpeed;
            
            // Drift is combination of swing and overall wind
            this.x += Math.sin(this.swingAngle) * this.swingRange + wind;
            this.rotation += this.rotationSpeed;

            // Recycle if off screen
            if (this.y > canvas.height + 10) {
                this.reset();
            }
            if (this.x < -10) {
                this.x = canvas.width + 5;
            } else if (this.x > canvas.width + 10) {
                this.x = -5;
            }
        }

        draw() {
            // Foreground flakes (large size/depth) are drawn with detailed geometric snowflake structure
            if (this.z > 0.75) {
                this.drawDetailedSnowflake();
            } else {
                this.drawSoftDotFlake();
            }
        }

        drawSoftDotFlake() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = this.color;
            ctx.shadowBlur = this.z > 0.4 ? 4 : 0;
            ctx.shadowColor = 'rgba(255, 255, 255, 0.4)';
            ctx.fill();
            ctx.shadowBlur = 0; // reset
        }

        drawDetailedSnowflake() {
            ctx.save();
            ctx.translate(this.x, this.y);
            ctx.rotate(this.rotation);
            ctx.strokeStyle = this.color;
            ctx.lineWidth = this.size * 0.15;
            ctx.lineCap = 'round';
            ctx.beginPath();
            
            const radius = this.size;
            
            // Draw 6 branches
            for (let i = 0; i < 6; i++) {
                ctx.moveTo(0, 0);
                ctx.lineTo(0, -radius);
                
                // Draw small side branches
                ctx.moveTo(0, -radius * 0.4);
                ctx.lineTo(-radius * 0.25, -radius * 0.65);
                ctx.moveTo(0, -radius * 0.4);
                ctx.lineTo(radius * 0.25, -radius * 0.65);
                
                ctx.moveTo(0, -radius * 0.7);
                ctx.lineTo(-radius * 0.18, -radius * 0.88);
                ctx.moveTo(0, -radius * 0.7);
                ctx.lineTo(radius * 0.18, -radius * 0.88);

                ctx.rotate(Math.PI / 3);
            }
            ctx.shadowBlur = 6;
            ctx.shadowColor = 'rgba(255, 255, 255, 0.6)';
            ctx.stroke();
            ctx.restore();
        }
    }

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initSnow();
    }

    function initSnow() {
        snowflakes = [];
        // Calculate density based on canvas area
        const count = Math.floor((canvas.width * canvas.height) / 8000) || 40;
        const cappedCount = Math.min(count, 140);
        for (let i = 0; i < cappedCount; i++) {
            snowflakes.push(new Snowflake(true));
        }
    }

    function animate() {
        time++;
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Slowly varying wind speed and direction over time
        const wind = Math.sin(time * 0.003) * 0.4 + 0.15;

        for (let i = 0; i < snowflakes.length; i++) {
            snowflakes[i].update(wind);
            snowflakes[i].draw();
        }

        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
