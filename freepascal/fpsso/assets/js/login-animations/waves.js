var animation = {
    name: 'คลื่น (Waves)',
    desc: 'เส้นคลื่นเคลื่อนไหวเลื่อนไหล',
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
    
    // Cleanup old animation if any
    if (window.ANIMATION_ACTIVE_IDS && window.ANIMATION_ACTIVE_IDS[canvasId]) {
        cancelAnimationFrame(window.ANIMATION_ACTIVE_IDS[canvasId]);
    }
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};
    
    let waves = [];
    let time = 0;

    function resizeCanvas() {
        canvas.width = sidebar.clientWidth;
        canvas.height = sidebar.clientHeight;
        initWaves();
    }

    class Wave {
        constructor(yOffset, amplitude, period, speed, color) {
            this.yOffset = yOffset;
            this.amplitude = amplitude;
            this.period = period;
            this.speed = speed;
            this.color = color;
        }
        draw(ctx, time) {
            ctx.beginPath();
            ctx.moveTo(0, this.yOffset + Math.sin(time * this.speed) * this.amplitude);
            for (let x = 0; x <= canvas.width; x += 10) {
                const y = this.yOffset + Math.sin(x * this.period + time * this.speed) * this.amplitude;
                ctx.lineTo(x, y);
            }
            ctx.strokeStyle = this.color;
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    function initWaves() {
        waves = [];
        const numWaves = 3;
        for (let i = 0; i < numWaves; i++) {
            waves.push(new Wave(
                canvas.height / 2 + (i * 20), 
                40 + i * 20, 
                0.005 + i * 0.002, 
                0.02 + i * 0.01, 
                `rgba(255, 255, 255, ${0.1 + i * 0.1})`
            ));
        }
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        time += 1;
        waves.forEach(wave => wave.draw(ctx, time));
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
