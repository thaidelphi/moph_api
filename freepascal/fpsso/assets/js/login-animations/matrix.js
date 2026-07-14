var animation = {
    name: 'เดอะ เมทริกซ์ (The Matrix)',
    desc: 'ฝนดิจิทัลตัวอักษรสีเขียวเรียงลงมา',
    icon: 'fas fa-terminal',
    characters_en: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', // ตัวอักษรภาษาอังกฤษและตัวเลข
    characters_th: 'กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหฬอฮ' // ตัวอักษรภาษาไทย
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
    const characters = (animation.characters_en || '') + (animation.characters_th || '') || 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const fontSize = 16;
    let columns = 0;
    let drops = [];

    class Drop {
        constructor(x) {
            this.x = x;
            this.y = Math.random() * height;
            this.speed = Math.random() * 3 + 1.5;
            this.chars = [];
            this.length = Math.floor(Math.random() * 15 + 10);
            for(let i=0; i<this.length; i++){
                this.chars.push(characters.charAt(Math.floor(Math.random() * characters.length)));
            }
        }
        update() {
            this.y += this.speed;
            
            // Check if fully off screen
            if (this.y - (this.length * fontSize) > height) {
                this.y = 0;
                this.speed = Math.random() * 3 + 1.5;
                this.length = Math.floor(Math.random() * 15 + 10);
            }
            
            // Shift characters forward to create flowing effect occasionally
            if (Math.random() < 0.3) {
                this.chars.unshift(characters.charAt(Math.floor(Math.random() * characters.length)));
                this.chars.pop();
            }
            
            // Randomly mutate some middle characters
            for (let i = 1; i < this.chars.length; i++) {
                if (Math.random() < 0.02) {
                    this.chars[i] = characters.charAt(Math.floor(Math.random() * characters.length));
                }
            }
        }
        draw(ctx) {
            for (let i = 0; i < this.chars.length; i++) {
                const charY = this.y - (i * fontSize);
                if (charY < -fontSize || charY > height + fontSize) continue;
                
                if (i === 0) {
                    ctx.fillStyle = '#fff'; // leading char is white
                    ctx.shadowBlur = 8;
                    ctx.shadowColor = '#fff';
                } else {
                    const opacity = Math.max(0, 1 - (i / this.length));
                    ctx.fillStyle = `rgba(34, 197, 94, ${opacity})`; // Matrix green (Tailwind emerald-500)
                    ctx.shadowBlur = 3;
                    ctx.shadowColor = '#22c55e';
                }
                ctx.fillText(this.chars[i], this.x, charY);
                ctx.shadowBlur = 0; // reset
            }
        }
    }

    function resizeCanvas() {
        width = canvas.width = sidebar.clientWidth;
        height = canvas.height = sidebar.clientHeight;
        columns = Math.floor(width / fontSize);
        drops = [];
        for(let x = 0; x < columns; x++) {
            drops.push(new Drop(x * fontSize));
        }
    }

    function animate() {
        ctx.clearRect(0, 0, width, height);
        ctx.font = 'bold ' + fontSize + 'px monospace';
        
        for(let i = 0; i < drops.length; i++) {
            drops[i].update();
            drops[i].draw(ctx);
        }
        
        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
