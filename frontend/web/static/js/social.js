/**
 * social.js — ソーシャル機能 (スキル検索, コラボボード, ランチマッチ, 交流マトリクス)
 */

// ======== Feature 1: スキルマッチング検索 ========
function initSkillSearch() {
    const input = document.getElementById('skill-search-input');
    const btn = document.getElementById('skill-search-btn');
    if (!btn || !input) return;

    btn.addEventListener('click', () => performSkillSearch(input.value.trim()));
    input.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') performSkillSearch(input.value.trim());
    });
}

async function performSkillSearch(skill) {
    if (!skill) return;
    const results = document.getElementById('skill-search-results');
    results.innerHTML = '<div class="social-loading">検索中...</div>';

    try {
        const res = await fetch(`/api/skill_search?skill=${encodeURIComponent(skill)}&include_position=true`);
        const data = await res.json();
        if (!Array.isArray(data) || data.length === 0) {
            results.innerHTML = '<div class="social-empty">該当するユーザーが見つかりません</div>';
            return;
        }
        results.innerHTML = data.map(u => `
            <div class="social-item">
                <div class="social-avatar">${avatarHtml(u.profile_image, u.user_name)}</div>
                <div class="social-info">
                    <strong>${esc(u.user_name || 'Unknown')}</strong>
                    <span class="social-sub">${esc(u.department || '')} / ${esc(u.job_title || '')}</span>
                </div>
                ${u.matched_skill ? `<span class="social-tag accent">${esc(u.matched_skill)}</span>` : ''}
                <span class="social-dot ${u.position && u.position.x != null ? 'online' : 'offline'}"></span>
            </div>
        `).join('');
    } catch (e) {
        results.innerHTML = '<div class="social-empty">検索エラー</div>';
    }
}

// ======== Feature 3: コラボレーションボード ========
function initCollabBoard() {
    const newBtn = document.getElementById('btn-new-collab-post');
    const form = document.getElementById('collab-new-post-form');
    const cancelBtn = document.getElementById('collab-cancel-btn');
    const submitBtn = document.getElementById('collab-submit-btn');
    if (!newBtn) return;

    newBtn.addEventListener('click', () => { form.style.display = form.style.display === 'none' ? 'block' : 'none'; });
    cancelBtn.addEventListener('click', () => { form.style.display = 'none'; });
    submitBtn.addEventListener('click', submitCollabPost);

    loadCollabPosts();
}

async function loadCollabPosts() {
    const list = document.getElementById('collab-post-list');
    if (!list) return;
    try {
        const res = await fetch('/api/collab_posts?status=open');
        const posts = await res.json();
        if (!Array.isArray(posts) || posts.length === 0) {
            list.innerHTML = '<div class="social-empty">投稿はまだありません</div>';
            return;
        }
        list.innerHTML = posts.map(p => {
            const typeLabel = { help_wanted: '助けを求む', reviewer_needed: 'レビュー依頼', pair_programming: 'ペアプロ', question: '質問', offer: 'お手伝い' }[p.post_type] || p.post_type;
            const skills = (p.required_skills || '').split(',').filter(s => s.trim()).map(s => `<span class="social-tag">${esc(s.trim())}</span>`).join('');
            return `
                <div class="social-item collab-post">
                    <div class="collab-header">
                        <span class="collab-type-badge type-${p.post_type}">${esc(typeLabel)}</span>
                        <strong>${esc(p.title)}</strong>
                        ${p.is_skill_match ? '<span class="social-tag accent">スキル一致</span>' : ''}
                    </div>
                    <div class="collab-meta">
                        <span>${esc(p.user_name || '')}</span>
                        <span>${(p.created_at || '').substring(0, 10)}</span>
                        ${p.response_count > 0 ? `<span class="collab-responses">💬 ${p.response_count}</span>` : ''}
                    </div>
                    ${p.description ? `<div class="collab-desc">${esc(p.description)}</div>` : ''}
                    ${skills ? `<div class="collab-skills">${skills}</div>` : ''}
                </div>
            `;
        }).join('');
    } catch (e) {
        list.innerHTML = '<div class="social-empty">読込エラー</div>';
    }
}

async function submitCollabPost() {
    const postType = document.getElementById('collab-post-type').value;
    const title = document.getElementById('collab-title').value.trim();
    const desc = document.getElementById('collab-desc').value.trim();
    const skills = document.getElementById('collab-skills').value.trim();
    if (!title) { alert('タイトルを入力してください'); return; }

    try {
        await fetch('/api/collab_posts', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                beacon_id: 'web_user',
                user_name: 'Web User',
                post_type: postType,
                title: title,
                description: desc,
                required_skills: skills
            })
        });
        document.getElementById('collab-new-post-form').style.display = 'none';
        document.getElementById('collab-title').value = '';
        document.getElementById('collab-desc').value = '';
        document.getElementById('collab-skills').value = '';
        loadCollabPosts();
    } catch (e) {
        alert('投稿に失敗しました');
    }
}

// ======== Feature 5: ランチ・コーヒーマッチング ========
function initLunchMatch() {
    const genBtn = document.getElementById('btn-generate-lunch');
    if (!genBtn) return;
    genBtn.addEventListener('click', generateLunchMatch);
    loadLunchMatches();
}

async function loadLunchMatches() {
    const content = document.getElementById('lunch-match-content');
    if (!content) return;
    try {
        const res = await fetch('/api/lunch_match/today?beacon_id=web_user');
        const data = await res.json();
        if (data.match) {
            const m = data.match;
            const p = m.partner || {};
            content.innerHTML = `
                <div class="social-item lunch-match-item">
                    <div class="social-avatar">${avatarHtml(p.profile_image, p.user_name)}</div>
                    <div class="social-info">
                        <strong>${esc(p.user_name || 'Unknown')}</strong>
                        <span class="social-sub">${esc(p.department || '')}</span>
                    </div>
                    <span class="social-tag ${m.status === 'accepted' ? 'accent' : ''}">${matchStatusLabel(m.status)}</span>
                </div>
                ${m.match_reason ? `<div class="lunch-reason">✨ ${esc(m.match_reason)}</div>` : ''}
            `;
        } else {
            content.innerHTML = '<div class="social-empty">今日のマッチはまだありません。「マッチを生成」ボタンで開始できます。</div>';
        }
    } catch (e) {
        content.innerHTML = '<div class="social-empty">読込エラー</div>';
    }
}

async function generateLunchMatch() {
    try {
        await fetch('/api/lunch_match/generate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ match_type: 'interest_based' })
        });
        loadLunchMatches();
    } catch (e) {
        alert('マッチ生成に失敗しました');
    }
}

function matchStatusLabel(s) {
    return { pending: '未回答', accepted: '承諾済', declined: '辞退', completed: '完了' }[s] || s;
}

// ======== Feature 4: 交流ヒートマップ (部門間マトリクス) ========
let currentInteractionHours = 168; // デフォルト: 7日間

function initInteractionSection() {
    loadInteractionStats(currentInteractionHours);

    const btnContainer = document.getElementById('interaction-period-btns');
    if (btnContainer) {
        btnContainer.addEventListener('click', (e) => {
            const btn = e.target.closest('.period-btn');
            if (!btn) return;
            btnContainer.querySelectorAll('.period-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            currentInteractionHours = parseInt(btn.dataset.hours, 10);
            loadInteractionStats(currentInteractionHours);
        });
    }
}

async function loadInteractionStats(hours) {
    const matrixEl = document.getElementById('interaction-matrix');
    const suggestEl = document.getElementById('interaction-suggestions');
    if (!matrixEl) return;

    try {
        const res = await fetch(`/api/interaction_stats?hours=${hours}`);
        const data = await res.json();

        // Department matrix table
        if (data.department_matrix) {
            // 全部門名を収集（トップレベル + ネストされたキー両方）
            const allDepts = new Set();
            for (const [d1, innerMap] of Object.entries(data.department_matrix)) {
                allDepts.add(d1);
                for (const d2 of Object.keys(innerMap)) {
                    allDepts.add(d2);
                }
            }
            const depts = [...allDepts].sort();
            if (depts.length > 0) {
                let html = '<table class="matrix-table"><thead><tr><th></th>';
                depts.forEach(d => { html += `<th>${esc(d.substring(0, 6))}</th>`; });
                html += '</tr></thead><tbody>';
                const maxCount = Math.max(1, ...depts.flatMap(r => depts.map(c => {
                    const [d1, d2] = [r, c].sort();
                    return data.department_matrix[d1]?.[d2] || 0;
                })));
                depts.forEach(rowDept => {
                    html += `<tr><td class="matrix-label">${esc(rowDept.substring(0, 8))}</td>`;
                    depts.forEach(colDept => {
                        const [d1, d2] = [rowDept, colDept].sort();
                        const count = data.department_matrix[d1]?.[d2] || 0;
                        const opacity = count / maxCount * 0.8;
                        html += `<td style="background: rgba(0,188,212,${opacity.toFixed(2)})">${count}</td>`;
                    });
                    html += '</tr>';
                });
                html += '</tbody></table>';
                matrixEl.innerHTML = html;
            } else {
                matrixEl.innerHTML = '<div class="social-empty">交流データを収集中...</div>';
            }
        } else {
            matrixEl.innerHTML = '<div class="social-empty">交流データを収集中...</div>';
        }

        // Suggestions
        if (suggestEl && data.suggestions && data.suggestions.length > 0) {
            suggestEl.innerHTML = data.suggestions.map(s =>
                `<div class="social-item suggestion-item">💡 ${esc(s.suggestion)}</div>`
            ).join('');
        }
    } catch (e) {
        matrixEl.innerHTML = '<div class="social-empty">読込エラー</div>';
    }
}

// ======== Utility ========
function esc(str) {
    if (!str) return '';
    const el = document.createElement('span');
    el.textContent = str;
    return el.innerHTML;
}

function avatarHtml(imagePath, name) {
    if (imagePath) {
        return `<img src="${imagePath}" class="social-avatar-img" alt="">`;
    }
    const initial = (name || '?').charAt(0);
    return `<div class="social-avatar-placeholder">${esc(initial)}</div>`;
}

// ======== Init ========
document.addEventListener('DOMContentLoaded', () => {
    initSkillSearch();
    initCollabBoard();
    initLunchMatch();
    initInteractionSection();

    const refreshBtn = document.getElementById('social-refresh-btn');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', () => {
            refreshBtn.classList.add('spinning');
            initCollabBoard();
            initLunchMatch();
            loadInteractionStats(currentInteractionHours);
            setTimeout(() => refreshBtn.classList.remove('spinning'), 600);
        });
    }
});
