var animation = {
    name: 'อวกาศ (Warp Speed)',
    desc: 'ดวงดาวพุ่งทะยานสไตล์อวกาศ',
    icon: 'fas fa-rocket'
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
    let stars = [];
    const numStars = 500; // Adjusted for sidebar size
    const baseSpeed = 2;
    
    let centerX, centerY;
    let mouseX, mouseY;

    function resize() {
        width = canvas.width = sidebar.clientWidth;
        height = canvas.height = sidebar.clientHeight;
        centerX = width / 2;
        centerY = height / 2;
        mouseX = centerX;
        mouseY = centerY;
    }
    window.addEventListener('resize', resize);
    resize();

    class Star {
        constructor() {
            this.reset();
        }
        reset() {
            this.x = (Math.random() - 0.5) * width * 2;
            this.y = (Math.random() - 0.5) * height * 2;
            this.z = Math.random() * width;
            this.pz = this.z;
        }
        update() {
            this.z -= baseSpeed;
            if (this.z < 1) {
                this.reset();
                this.pz = this.z;
            }
        }
        draw() {
            let sx = (this.x / this.z) * (width / 2) + mouseX;
            let sy = (this.y / this.z) * (height / 2) + mouseY;
            let px = (this.x / this.pz) * (width / 2) + mouseX;
            let py = (this.y / this.pz) * (height / 2) + mouseY;
            let size = (1 - this.z / width) * 2;

            ctx.beginPath();
            ctx.strokeStyle = `rgba(255, 255, 255, ${1 - this.z / width})`;
            ctx.lineWidth = size;
            ctx.moveTo(px, py);
            ctx.lineTo(sx, sy);
            ctx.stroke();

            this.pz = this.z;
        }
    }

    for (let i = 0; i < numStars; i++) {
        stars.push(new Star());
    }

    sidebar.addEventListener('mousemove', (e) => {
        const rect = sidebar.getBoundingClientRect();
        mouseX += (e.clientX - rect.left - mouseX) * 0.05;
        mouseY += (e.clientY - rect.top - mouseY) * 0.05;
    });

    sidebar.addEventListener('mouseleave', () => {
        mouseX = width / 2;
        mouseY = height / 2;
    });

    function animate() {
        ctx.clearRect(0, 0, width, height);

        for (let star of stars) {
            star.update();
            star.draw();
        }

        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    animate();
})();
