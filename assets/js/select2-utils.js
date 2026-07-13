/**
 * ERP Select2 Utilities
 * Reusable templates for Employee Search and other selection components
 */

const Select2Utils = {
    // Default avatar placeholder path
    get DEFAULT_AVATAR() {
        return (typeof BASE_URL !== 'undefined' ? BASE_URL : '') + 'assets/img/default_avatar.png';
    },

    /**
     * Template for displaying employee in the dropdown list
     */
    formatEmployee: function(repo) {
        if (repo.loading) return repo.text;
        
        let avatarUrl = repo.avatar;
        if (!avatarUrl && repo.element && $(repo.element).data('avatar')) {
            avatarUrl = $(repo.element).data('avatar');
        }

        let initials = repo.initials;
        if (!initials && repo.element && $(repo.element).data('initials')) {
            initials = $(repo.element).data('initials');
        }

        let position = repo.position;
        if (!position && repo.element && $(repo.element).data('position')) {
            position = $(repo.element).data('position');
        }
        position = position || '-';

        let avatarHtml = '';
        if (avatarUrl && avatarUrl.indexOf('default_avatar') === -1) {
            avatarHtml = `<div class="avatar" style="width: 32px; height: 32px; border-radius: 50%; background-image: url('${avatarUrl}'); background-size: cover; background-position: center; flex-shrink: 0;"></div>`;
        } else if (initials) {
            let nameForColor = repo.text || 'A';
            let hash = 0;
            for (let i = 0; i < nameForColor.length; i++) { hash = nameForColor.charCodeAt(i) + ((hash << 5) - hash); }
            let color = '#' + ('00000' + (hash & 0x00FFFFFF).toString(16)).slice(-6);
            avatarHtml = `<div class="avatar" style="width: 32px; height: 32px; border-radius: 50%; background-color: ${color}; color: white; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 0.9rem; flex-shrink: 0;">${initials}</div>`;
        } else {
            avatarHtml = `<div class="avatar" style="width: 32px; height: 32px; border-radius: 50%; background-image: url('${Select2Utils.DEFAULT_AVATAR}'); background-size: cover; background-position: center; flex-shrink: 0;"></div>`;
        }

        return $(`
            <div style="display: flex; align-items: center; gap: 12px; padding: 4px 0;">
                ${avatarHtml}
                <div class="user-info" style="overflow: hidden;">
                    <div class="name" style="font-weight: 600; font-size: 0.9rem; color: #1e293b; white-space: nowrap; text-overflow: ellipsis; overflow: hidden;">${repo.text}</div>
                    <div class="pos" style="font-size: 0.75rem; color: #64748b; white-space: nowrap; text-overflow: ellipsis; overflow: hidden;">${position}</div>
                </div>
            </div>
        `);
    },

    /**
     * Template for displaying selected employee in the box
     */
    formatEmployeeSelection: function(repo) {
        if (!repo.id) return repo.text;
        
        // As requested by user: Keep avatars disabled for the vehicles module
        if (window.location.href.indexOf('/modules/vehicles/') !== -1) {
            return repo.text;
        }
        let avatarUrl = repo.avatar_url;
        if (!avatarUrl && repo.element && $(repo.element).data('avatar')) {
            avatarUrl = $(repo.element).data('avatar');
        }

        let initials = repo.initials;
        if (!initials && repo.element && $(repo.element).data('initials')) {
            initials = $(repo.element).data('initials');
        }
        
        if (!initials && !avatarUrl && repo.text) {
            const parts = repo.text.replace(/^(นาย|นาง|น\.ส\.|นางสาว|ด\.ช\.|ด\.ญ\.)\s*/, '').trim().split(' ');
            if (parts.length >= 2) {
                initials = parts[0].charAt(0) + parts[1].charAt(0);
            } else if (parts.length === 1 && parts[0].length >= 2) {
                initials = parts[0].substring(0, 2);
            } else {
                initials = 'U';
            }
        }

        let avatarHtml = '';
        if (avatarUrl && avatarUrl.indexOf('default_avatar') === -1) {
            avatarHtml = `<div class="avatar" style="width: 20px; height: 20px; border-radius: 50%; background-image: url('${avatarUrl}'); background-size: cover; background-position: center; display: inline-block; vertical-align: middle; margin-right: 6px;"></div>`;
        } else if (initials) {
            let nameForColor = repo.text || 'A';
            let hash = 0;
            for (let i = 0; i < nameForColor.length; i++) { hash = nameForColor.charCodeAt(i) + ((hash << 5) - hash); }
            let color = '#' + ('00000' + (hash & 0x00FFFFFF).toString(16)).slice(-6);
            avatarHtml = `<div class="avatar" style="width: 20px; height: 20px; border-radius: 50%; background-color: ${color}; color: white; display: inline-flex; align-items: center; justify-content: center; font-weight: bold; font-size: 0.6rem; vertical-align: middle; margin-right: 6px;">${initials}</div>`;
        } else {
            avatarHtml = `<div class="avatar" style="width: 20px; height: 20px; border-radius: 50%; background-image: url('${Select2Utils.DEFAULT_AVATAR}'); background-size: cover; background-position: center; display: inline-block; vertical-align: middle; margin-right: 6px;"></div>`;
        }

        return $(`<span style="display: inline-flex; align-items: center;">${avatarHtml}<span>${repo.text}</span></span>`);
    },

    /**
     * Initialize standard employee search
     * @param {string|jQuery} selector - CSS selector or jQuery object
     * @param {object} options - Custom options to override defaults
     */
    initEmployeeSearch: function(selector, options = {}) {
        const $el = $(selector);
        const isMultiple = options.multiple || $el.prop('multiple');

        const defaults = {
            ajax: {
                url: (typeof BASE_URL !== 'undefined' ? BASE_URL : '') + 'modules/settings/get_employees.php',
                dataType: 'json',
                delay: 250,
                data: function (params) {
                    return {
                        q: params.term,
                        page: params.page || 1
                    };
                },
                processResults: function (data, params) {
                    params.page = params.page || 1;
                    return {
                        results: data.results,
                        pagination: {
                            more: (params.page * 20) < data.total_count
                        }
                    };
                },
                cache: true
            },
            placeholder: 'ค้นหาชื่อหรือตำแหน่ง...',
            allowClear: true,
            minimumInputLength: 1,
            templateResult: Select2Utils.formatEmployee,
            templateSelection: Select2Utils.formatEmployeeSelection,
            width: '100%',
            closeOnSelect: !isMultiple // Don't close if multiple selection is enabled
        };

        const settings = $.extend(true, {}, defaults, options);
        return $el.select2(settings);
    },

    /**
     * Initialize local employee select (for pre-populated HTML <select>)
     * @param {string|jQuery} selector - CSS selector or jQuery object
     * @param {object} options - Custom options to override defaults
     */
    initEmployeeLocalSelect: function(selector, options = {}) {
        const $el = $(selector);
        const isMultiple = options.multiple || $el.prop('multiple');

        const defaults = {
            placeholder: 'ค้นหาและเลือกรายชื่อ...',
            allowClear: true,
            templateResult: Select2Utils.formatEmployee,
            templateSelection: Select2Utils.formatEmployeeSelection,
            width: '100%',
            closeOnSelect: !isMultiple,
            dropdownCssClass: 'employee-select-dropdown'
        };

        const settings = $.extend(true, {}, defaults, options);
        return $el.select2(settings);
    },

    /**
     * Template for displaying vehicle in the dropdown list
     */
    formatVehicle: function(repo) {
        if (!repo.id) return repo.text;
        
        let photoUrl = repo.photo;
        if (!photoUrl && repo.element && $(repo.element).data('photo')) {
            photoUrl = $(repo.element).data('photo');
        }

        const baseUrl = typeof BASE_URL !== 'undefined' ? BASE_URL : '';

        if (photoUrl) {
            return $(`
                <div style="display: flex; align-items: center; gap: 12px; padding: 4px 0; position: relative;">
                    <div class="vehicle-photo-preview" style="width: 48px; height: 32px; border-radius: 4px; background-image: url('${baseUrl}uploads/vehicle/${photoUrl}'); background-size: cover; background-position: center; flex-shrink: 0; box-shadow: 0 1px 2px rgba(0,0,0,0.1); border: 1px solid #e2e8f0; position: relative; z-index: 1;"></div>
                    <div class="user-info" style="overflow: hidden; width: 100%;">
                        <div class="name" style="font-weight: 600; font-size: 0.85rem; color: #1e293b; white-space: normal; line-height: 1.2;">${repo.text}</div>
                    </div>
                </div>
            `);
        } else {
            return $(`
                <div style="display: flex; align-items: center; gap: 12px; padding: 4px 0;">
                    <div style="width: 48px; height: 32px; border-radius: 4px; background-color: #f1f5f9; display: flex; align-items: center; justify-content: center; flex-shrink: 0; border: 1px solid #e2e8f0;">
                        <i class="fas fa-car" style="color: #94a3b8; font-size: 14px;"></i>
                    </div>
                    <div class="user-info" style="overflow: hidden; width: 100%;">
                        <div class="name" style="font-weight: 600; font-size: 0.85rem; color: #1e293b; white-space: normal; line-height: 1.2;">${repo.text}</div>
                    </div>
                </div>
            `);
        }
    },

    /**
     * Template for displaying selected vehicle in the box
     */
    formatVehicleSelection: function(repo) {
        if (!repo.id) return repo.text;
        
        // Return only the text (no photo) for the selected item box
        // as requested by the user: "เมื่อเลือกเสร็จแล้ว ไม่ต้องแสดงรูปรถ กับ avatar ให้เห็นเฉพาะตอน list เลือก"
        return repo.text;
    },

    /**
     * Initialize local vehicle select
     */
    initVehicleLocalSelect: function(selector, options = {}) {
        const $el = $(selector);
        
        const defaults = {
            placeholder: 'เลือกรถยนต์...',
            allowClear: true,
            templateResult: Select2Utils.formatVehicle,
            templateSelection: Select2Utils.formatVehicleSelection,
            width: '100%',
            dropdownCssClass: 'vehicle-select-dropdown'
        };

        const settings = $.extend(true, {}, defaults, options);
        return $el.select2(settings);
    }
};
