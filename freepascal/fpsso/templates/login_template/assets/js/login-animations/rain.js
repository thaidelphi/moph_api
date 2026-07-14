var animation = {
    name: 'พายุฝนและน้ำท่วม (Rain & Rising Water)',
    desc: 'พายุฝนตกลงมาพร้อมกับระดับน้ำที่ค่อยๆ สูงขึ้น',
    icon: 'fas fa-cloud-showers-heavy'
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
    let raindrops = [];
    let splashes = [];
    let waterLevel = 0; // Starts at 0 (bottom)

    class Raindrop {
        constructor() {
            this.reset(true);
        }
        reset(randomY = false) {
            this.x = Math.random() * width;
            this.y = randomY ? Math.random() * height : -20;
            this.z = Math.random() * 0.5 + 0.5; // depth for parallax (0.5 to 1.0)
            this.len = this.z * 20 + 10;
            this.speed = this.z * 15 + 10;
            this.color = `rgba(148, 163, 184, ${this.z * 0.6 + 0.2})`; // slate-400 with varying opacity
        }
        update() {
            this.y += this.speed;
            
            // Check collision with water level
            const surfaceY = height - waterLevel;
            if (this.y + this.len >= surfaceY) {
                // Create splash only if water is visible
                if (waterLevel > 0 && Math.random() < 0.3) {
                    splashes.push(new Splash(this.x, surfaceY));
                }
                this.reset();
            }
        }
        draw(ctx) {
            ctx.beginPath();
            ctx.moveTo(this.x, this.y);
            ctx.lineTo(this.x, this.y + this.len);
            ctx.strokeStyle = this.color;
            ctx.lineWidth = this.z * 1.5;
            ctx.stroke();
        }
    }

    class Splash {
        constructor(x, y) {
            this.x = x;
            this.y = y;
            this.radius = 1;
            this.maxRadius = Math.random() * 8 + 4;
            this.speed = Math.random() * 0.5 + 0.2;
            this.opacity = 0.5;
        }
        update() {
            this.radius += this.speed;
            this.opacity -= 0.02;
        }
        draw(ctx) {
            if (this.opacity <= 0) return;
            ctx.beginPath();
            // Flatten the circle to look like an ellipse on the water surface
            ctx.ellipse(this.x, this.y, this.radius * 2, this.radius * 0.5, 0, 0, Math.PI * 2);
            ctx.strokeStyle = `rgba(226, 232, 240, ${this.opacity})`; // slate-200
            ctx.lineWidth = 1;
            ctx.stroke();
        }
    }

    function resizeCanvas() {
        width = canvas.width = sidebar.clientWidth;
        height = canvas.height = sidebar.clientHeight;
        
        const dropCount = Math.floor((width * height) / 2500); // Dense rain
        raindrops = [];
        for(let i = 0; i < dropCount; i++) {
            raindrops.push(new Raindrop());
        }
    }

    // Water properties
    const waterColor = 'rgba(14, 165, 233, 0.4)'; // sky-500 with opacity
    const waterColorDeep = 'rgba(2, 132, 199, 0.7)'; // sky-600
    
    // Wave variables
    let time = 0;

    function animate() {
        ctx.clearRect(0, 0, width, height);
        
        // Update and draw raindrops
        for(let i = 0; i < raindrops.length; i++) {
            raindrops[i].update();
            raindrops[i].draw(ctx);
        }
        
        // Update and draw splashes
        for(let i = splashes.length - 1; i >= 0; i--) {
            splashes[i].update();
            splashes[i].draw(ctx);
            if (splashes[i].opacity <= 0) {
                splashes.splice(i, 1);
            }
        }
        
        // Draw rising water
        waterLevel += 0.2; // Speed of rising water
        if (waterLevel > height + 100) {
            waterLevel = 0; // Reset flood when it covers the screen
        }
        
        // Draw water surface waves
        time += 0.05;
        const surfaceY = height - waterLevel;
        
        if (waterLevel > 0) {
            ctx.beginPath();
            ctx.moveTo(0, surfaceY);
            
            // Draw undulating surface
            for (let x = 0; x <= width; x += 20) {
                const y = surfaceY + Math.sin(x * 0.02 + time) * 4;
                ctx.lineTo(x, y);
            }
            // Ensure the water surface reaches the exact right edge
            ctx.lineTo(width, surfaceY + Math.sin(width * 0.02 + time) * 4);
            
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            
            // Gradient for water depth
            const grad = ctx.createLinearGradient(0, surfaceY, 0, height);
            grad.addColorStop(0, waterColor);
            grad.addColorStop(1, waterColorDeep);
            
            ctx.fillStyle = grad;
            ctx.fill();
        }

        // Random Lightning Flash
        if (Math.random() < 0.003) {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
            ctx.fillRect(0, 0, width, height);
        }
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
