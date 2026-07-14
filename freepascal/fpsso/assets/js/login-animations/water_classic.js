var animation = {
    name: 'คลื่นน้ำสมจริง (Classic Water Effect)',
    desc: 'เอฟเฟกต์คลื่นน้ำตกกระทบจากโค้ด Delphi (เลื่อนเมาส์หรือคลิกเพื่อสร้างคลื่น)',
    icon: 'fas fa-tint'
};

(function() {
    const currentScript = document.currentScript;
    const canvasId = (currentScript && currentScript.dataset.canvasId) || window.ANIMATION_CANVAS_ID || 'sidebar-canvas';
    const containerSelector = (currentScript && currentScript.dataset.containerSelector) || window.ANIMATION_CONTAINER_SELECTOR || '.login-sidebar';
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const sidebar = document.querySelector(containerSelector);
    if (!sidebar) return;
    
    // Cleanup old animation
    if (window.ANIMATION_ACTIVE_IDS && window.ANIMATION_ACTIVE_IDS[canvasId]) {
        cancelAnimationFrame(window.ANIMATION_ACTIVE_IDS[canvasId]);
    }
    // Remove old listeners
    if (window.ANIMATION_CLICK_HANDLER && window.ANIMATION_CLICK_HANDLER[canvasId]) {
        canvas.removeEventListener('click', window.ANIMATION_CLICK_HANDLER[canvasId]);
        canvas.removeEventListener('mousedown', window.ANIMATION_CLICK_HANDLER[canvasId]);
        sidebar.removeEventListener('click', window.ANIMATION_CLICK_HANDLER[canvasId]);
        sidebar.removeEventListener('mousedown', window.ANIMATION_CLICK_HANDLER[canvasId]);
    }
    if (window.ANIMATION_HOVER_HANDLER && window.ANIMATION_HOVER_HANDLER[canvasId]) {
        canvas.removeEventListener('mousemove', window.ANIMATION_HOVER_HANDLER[canvasId]);
        sidebar.removeEventListener('mousemove', window.ANIMATION_HOVER_HANDLER[canvasId]);
    }
    
    window.ANIMATION_ACTIVE_IDS = window.ANIMATION_ACTIVE_IDS || {};
    window.ANIMATION_CLICK_HANDLER = window.ANIMATION_CLICK_HANDLER || {};
    window.ANIMATION_HOVER_HANDLER = window.ANIMATION_HOVER_HANDLER || {};
    
    let width, height;
    let buffer1, buffer2;
    let outputImageData;
    let isDragging = false;

    function resizeCanvas() {
        width = canvas.width = sidebar.clientWidth || 300;
        height = canvas.height = sidebar.clientHeight || 150;
        
        if (width <= 0) width = canvas.width = 300;
        if (height <= 0) height = canvas.height = 150;
        
        buffer1 = new Int32Array(width * height);
        buffer2 = new Int32Array(width * height);
        
        outputImageData = ctx.createImageData(width, height);
    }

    // "Blob" function matching Delphi
    function drop(x, y, radius, weight) {
        if (x < radius || x > width - radius || y < radius || y > height - radius) return;
        let r2 = radius * radius;
        for (let cy = -radius; cy <= radius; cy++) {
            for (let cx = -radius; cx <= radius; cx++) {
                if (cx * cx + cy * cy <= r2) {
                    buffer1[(y + cy) * width + (x + cx)] += weight;
                }
            }
        }
    }

    function animate() {
        let i = width; // Skip first row
        for (let y = 1; y < height - 1; y++) {
            for (let x = 1; x < width - 1; x++) {
                // Delphi CalcWater algorithm:
                // NewH := (P1[xl] + P1[x] + P1[xr] + P2[xl] + P2[xr] + P3[xl] + P3[x] + P3[xr]) div 4 - P[x];
                let newH = (
                    buffer1[i - width - 1] + buffer1[i - width] + buffer1[i - width + 1] +
                    buffer1[i - 1]                              + buffer1[i + 1] +
                    buffer1[i + width - 1] + buffer1[i + width] + buffer1[i + width + 1]
                ) >> 2; // div 4
                
                newH -= buffer2[i];
                
                // Rate div 256. If damping is 20, Rate = (100-20)*256/100 = 204.
                // 204 / 256 is roughly 0.796. Let's use subtraction damping to avoid floats
                // buffer2[i] = newH - (newH >> 5) is roughly 0.96. We'll use 0.96 for smoother ripples
                newH -= (newH >> 5); 
                buffer2[i] = newH;
                
                i++;
            }
            i += 2; // skip edge pixels
        }

        // Swap buffers
        let temp = buffer1;
        buffer1 = buffer2;
        buffer2 = temp;

        // DrawWater algorithm (Transparent shading)
        let pDst = outputImageData.data;
        
        i = width;
        for (let y = 1; y < height - 1; y++) {
            for (let x = 1; x < width - 1; x++) {
                let dx = buffer1[i - 1] - buffer1[i + 1];
                let dy = buffer1[i - width] - buffer1[i + width];
                
                let dstIdx = i << 2;
                
                if (dx === 0 && dy === 0) {
                    pDst[dstIdx + 3] = 0; // Transparent
                } else {
                    let light = dx; 
                    
                    if (light < 0) {
                        // Highlight (White)
                        pDst[dstIdx] = 255;
                        pDst[dstIdx + 1] = 255;
                        pDst[dstIdx + 2] = 255;
                        pDst[dstIdx + 3] = Math.min(255, -light * 2);
                    } else {
                        // Shadow (Black)
                        pDst[dstIdx] = 0;
                        pDst[dstIdx + 1] = 0;
                        pDst[dstIdx + 2] = 0;
                        pDst[dstIdx + 3] = Math.min(255, light * 2);
                    }
                }
                
                i++;
            }
            // Edges (left unchanged/transparent)
            pDst[(i) << 2] = 0;
            pDst[(i+1) << 2] = 0;
            pDst[(i+2) << 2] = 0;
            pDst[(i+3) << 2] = 0;
            i += 2; 
        }

        ctx.putImageData(outputImageData, 0, 0);

        // Random rain drops
        if (Math.random() < 0.05) {
            drop(Math.floor(Math.random() * width), Math.floor(Math.random() * height), 3, 300);
        }

        window.ANIMATION_ACTIVE_IDS[canvasId] = requestAnimationFrame(animate);
    }

    function handleMouseMove(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        const rect = canvas.getBoundingClientRect();
        let x = Math.floor(e.clientX - rect.left);
        let y = Math.floor(e.clientY - rect.top);
        
        if (isDragging) {
            drop(x, y, 6, 800); // Stronger effect when dragging
        } else {
            drop(x, y, 3, 150); // Subtle effect on hover
        }
    }

    function handleMouseDown(e) {
        if (e.target.closest && e.target.closest('button, a, input, select, .nav-user')) return;
        isDragging = true;
        const rect = canvas.getBoundingClientRect();
        let x = Math.floor(e.clientX - rect.left);
        let y = Math.floor(e.clientY - rect.top);
        drop(x, y, 8, 1000); // Large drop on click
    }
    
    function handleMouseUp(e) {
        isDragging = false;
    }
    
    function handleMouseLeave(e) {
        isDragging = false;
    }

    // Keep references to remove them later if needed
    window.ANIMATION_HOVER_HANDLER[canvasId] = handleMouseMove;
    window.ANIMATION_CLICK_HANDLER[canvasId] = handleMouseDown;
    
    // We add events to 'sidebar' (the container) because the canvas might have pointer-events: none (e.g. in navbar)
    sidebar.addEventListener('mousemove', handleMouseMove);
    sidebar.addEventListener('mousedown', handleMouseDown);
    window.addEventListener('mouseup', handleMouseUp);
    sidebar.addEventListener('mouseleave', handleMouseLeave);

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
    animate();
})();
