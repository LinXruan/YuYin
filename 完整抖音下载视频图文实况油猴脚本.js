// ==UserScript==
// @name               Douyin 抖音浏览助手
// @name:zh-CN         Douyin 抖音浏览助手
// @name:en            Douyin Enhancer Tools
// @description        增强功能：查看封面、下载音乐、下载视频、下载图文、下载文章、用户主页批量下载、个人收藏页批量下载。
// @description:zh-CN  增强功能：查看封面、下载音乐、下载视频、下载图文、下载文章、用户主页批量下载、个人收藏页批量下载。
// @description:en     Enhanced Features: View cover art, download music, download videos, download photo albums, download articles, batch download from user profiles, batch download from personal favorites page.
// @namespace          https://www.runningcheese.com/userscripts
// @author             RunningCheese
// @version            2.7
// @match              http*://www.douyin.com/*
// @match              http*://douyin.com/*
// @match              http*://tts.byylook.com/*
// @icon               https://t1.gstatic.cn/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&size=32&url=https://www.douyin.com
// @grant              GM_setValue
// @grant              GM_getValue
// @grant              GM_registerMenuCommand
// @grant              GM_xmlhttpRequest
// @grant              GM_addStyle
// @require            https://cdnjs.cloudflare.com/ajax/libs/jszip/3.9.1/jszip.min.js
// @connect            iesdouyin.com
// @connect            douyinpic.com
// @connect            *.douyinpic.com
// @connect            ibytedtos.com
// @connect            *.ibytedtos.com
// @run-at             document-start
// @license            MIT
// @downloadURL https://update.greasyfork.org/scripts/577421/Douyin%20%E6%8A%96%E9%9F%B3%E6%B5%8F%E8%A7%88%E5%8A%A9%E6%89%8B.user.js
// @updateURL https://update.greasyfork.org/scripts/577421/Douyin%20%E6%8A%96%E9%9F%B3%E6%B5%8F%E8%A7%88%E5%8A%A9%E6%89%8B.meta.js
// ==/UserScript==

(function() {
    'use strict';

    // === 文案提取站自动化：页面打开后自动提取视频文案 ===
    if (location.hostname === 'tts.byylook.com' && location.pathname.startsWith('/ai/text-to-speech')) {
        (async () => {
            // 读取从抖音页面传递过来的视频链接
            const videoUrl = (() => {
                try { return GM_getValue('dy_tts_video_url', '抖音视频链接'); }
                catch (e) { return '抖音视频链接'; }
            })();

            // 等待指定元素出现（带超时）
            const waitFor = (selector, timeout) => new Promise(resolve => {
                const start = Date.now();
                const check = () => {
                    const el = document.querySelector(selector);
                    if (el) return resolve(el);
                    if (Date.now() - start > timeout) return resolve(null);
                    setTimeout(check, 200);
                };
                check();
            });

            // 点击指定选择器的元素
            const clickSelector = async (selector, timeout) => {
                const el = await waitFor(selector, timeout);
                if (el) {
                    try { el.click(); } catch (e) {}
                }
                return el;
            };

            try {
                // 1. 点击"文案提取"图标，打开输入区域
                await clickSelector('[class="iconfont icon-wenzitiqu1"]', 10000);
                await new Promise(r => setTimeout(r, 500));

                // 2. 填入抖音视频链接
                let input = await waitFor('[rows="7"]', 10000);
                if (input) {
                    input.innerText = videoUrl;
                    input.dispatchEvent(new Event("input"));
                    input.dispatchEvent(new Event("change"));
                }

                // 3. 点击提取按钮
                await clickSelector('[class="el-button el-button--primary"]', 10000);
                await new Promise(r => setTimeout(r, 500));

                // 4. 点击复制结果按钮
                await clickSelector('[class="el-button el-button--success"]', 10000);
            } catch (e) {
                console.error('[Douyin助手] 文案提取自动化失败:', e);
            }
        })();
        return; // 不在抖音页面执行后续逻辑
    }

    let ttPolicy;
    if (window.trustedTypes && window.trustedTypes.createPolicy) {
        try {
            ttPolicy = window.trustedTypes.createPolicy('dy-assistant-' + Math.random().toString(36).substring(2, 9), {
                createHTML: (string) => string
            });
        } catch (e) {
            ttPolicy = { createHTML: (string) => string };
        }
    } else {
        ttPolicy = { createHTML: (string) => string };
    }

    // 简化的元素创建工具
    const elements = {
        createAs(nodeType, config, appendTo) {
            const element = document.createElement(nodeType);
            if (config) {
                Object.entries(config).forEach(([key, value]) => {
                    if (key === 'innerHTML') {
                        element.innerHTML = ttPolicy.createHTML(value);
                    } else {
                        element[key] = value;
                    }
                });
            }
            if (appendTo) appendTo.appendChild(element);
            return element;
        }
    };


    // ═══════════════════════════════════════════
    //  Module A: 主页批量下载
    // ═══════════════════════════════════════════

    (function() {

        // ── constants ──
        const uRe = /^\/user\//;
        const E = {
            A: "/aweme/v1/web/user/profile/other",
            B: "/aweme/v1/web/user/profile/self",
            C: "/aweme/v1/web/aweme/post/",
            D: "/aweme/v1/web/aweme/article/",
            F: "/aweme/v1/web/aweme/favorite/",
            G: "/aweme/v1/web/aweme/like/",
        };
        const Fw = ["favorite", "collection", "fav_", "/fav/"];
        const Rw = ["/feed/", "recommend", "/rec/", "record", "watch_later"];
        const Rs = () => { const q = window.location.search; return q.includes("showTab=record") || q.includes("showTab=watch_later"); };
        const T = { v: "视频", i: "图文", a: "文章" };

        const ZS = 100 * 1024 * 1024;
        const DC = 3;

        const S = {
            cp: window.location.pathname,
            cid: "",
            vs: new Map(),
            dl: false,
            enabled: false,
            ver: 0,  // page version: guards against stale API responses from previous user page
        };

        // ── helpers ──
        const nt = (v, fb = "") => v === null || v === undefined ? fb : String(v);
        const up = () => uRe.test(window.location.pathname);
        const sp = () => window.location.pathname === "/user/self";
        const sf = (v, fb = "未命名", ml = 80) => { const c = nt(v, fb).replace(/[\\/:*?"<>|\s]+/g, "").replace(/\.+$/g, "").slice(0, ml); return c || fb; };
        const gE = (url, fb) => { try { const m = /\.([a-z0-9]{2,5})$/i.exec(new URL(url, window.location.href).pathname); return m ? m[1].toLowerCase() : fb; } catch (_) { return fb; } };
        const sl = (ms) => new Promise((r) => setTimeout(r, ms));
        const fu = (inp) => { if (typeof inp === "string") return inp; if (inp instanceof URL) return inp.href; return nt(inp?.url); };
        const pj = (txt, _) => { try { return JSON.parse(txt); } catch (e) { return null; } };

        const fU = (c) => Array.isArray(c?.url_list) ? nt(c.url_list[0]) : "";
        const lU = (c) => { if (!Array.isArray(c?.url_list) || c.url_list.length === 0) return ""; return nt(c.url_list[c.url_list.length - 1]); };

        const gn = (aw = {}) => { const r = aw.itl || aw.cap || aw.dsc || aw.aid || "未命名作品"; return sf(r, nt(aw.aid, "未命名作品"), 27).replace(/\.\d+$/g, ""); };

        const fa = (it = {}) => {
            const vd = it.video || {};
            const imgs = Array.isArray(it.images) ? it.images.map(lU).filter(Boolean) : null;
            const hi = Boolean(imgs?.length);
            const hv = Boolean(fU(vd.play_addr));
            let tp;
            if (hi) tp = T.i;
            else if (hv) tp = T.v;
            else tp = T.a;
            return {
                aid: nt(it.aweme_id),
                itl: nt(it.item_title),
                cap: nt(it.caption),
                dsc: nt(it.desc),
                tp,
                url: hv ? fU(vd.play_addr) : "",
                imgs,
                uid: nt(it.author?.uid),
                nick: nt(it.author?.nickname, "未知作者"),
            };
        };

        const fd = (ui = {}) => ({ uid: nt(ui.uid), nick: nt(ui.nickname) });

        // ── state management ──
        const rs = () => { S.cp = window.location.pathname; S.cid = ""; S.vs.clear(); rv(); };
        const es = () => { if (S.cp !== window.location.pathname) rs(); };

        // ── toast ──
        let _t = null;
        const tst = (msg, sticky) => {
            let el = document.getElementById("dy-toast");
            if (!el) {
                el = document.createElement("div");
                el.id = "dy-toast";
                el.style.cssText = "position:fixed;top:5%;left:50%;transform:translateX(-50%);background:#3F7FEA;color:#fff;padding:16px 18px;min-height:20px;min-width:180px;line-height:1.2;border-radius:13px;font-size:14px;font-family:sans-serif;z-index:2147483647;pointer-events:none;opacity:0;transition:opacity 0.25s ease;box-shadow:0 2px 8px rgba(0,122,255,0.25),0 0 0 0.5px rgba(0,122,255,0.1);box-sizing:border-box;display:flex;align-items:center;justify-content:center;";
                document.body.appendChild(el);
            }
            clearTimeout(_t);
            el.textContent = msg;
            el.style.opacity = "1";
            if (!sticky) { _t = setTimeout(() => { el.style.opacity = "0"; }, 1500); }
        };

        // ── network hooks ──
        const su = (url) => {
            if (!up()) return false;
            if (Object.values(E).some((p) => url.includes(p))) {
                // "喜欢"内容仅限自己的主页，避免在别人主页时混入自己的喜欢数据
                if (url.includes(E.G) && !sp()) return false;
                return true;
            }
            if (sp()) {
                if (Fw.some((kw) => url.includes(kw))) return true;
                if (Rw.some((kw) => url.includes(kw))) return true;
                if (Rs() && url.includes("/aweme/")) return true;
            }
            return false;
        };

        const ha = (url, txt) => {
            if (!su(url)) return;
            es();
            const d = pj(txt, url);
            if (!d) return;
            if (url.includes(E.A) || url.includes(E.B)) {
                // 在别人主页时忽略 self profile 响应（返回的是登录用户自己的 uid，会清空当前页面数据）
                if (url.includes(E.B) && !sp()) return;
                si(fd(d.user || {}));
            } else if (url.includes(E.D)) {
                const lst = d.aweme_list || d.article_list || [];
                if (!Array.isArray(lst)) return;
                lst.map((i) => { const x = fa(i); x.itl = x.itl || nt(i.article_title) || nt(i.title); x.dsc = x.dsc || nt(i.article_desc) || nt(i.desc_abstract); return x; }).forEach((a) => { if (!sp() && S.cid && a.uid && a.uid !== S.cid) return; if (a.aid) S.vs.set(a.aid, a); });
                rv();
            } else if (url.includes(E.C) || url.includes(E.G)) {
                if (!Array.isArray(d.aweme_list)) return;
                d.aweme_list.map(fa).forEach((v) => { if (!sp() && S.cid && v.uid && v.uid !== S.cid) return; if (v.aid) S.vs.set(v.aid, v); });
                rv();
            } else if (url.includes(E.F) || Fw.some((kw) => url.includes(kw))) {
                const lst = d.aweme_list || d.media_list || d.collection_list || d.fav_list || [];
                if (!Array.isArray(lst)) return;
                lst.map((i) => { const aw = i.aweme_info || i.aweme || i; const v = fa(aw); v.itl = v.itl || nt(i.title) || nt(i.collection_name); return v; }).forEach((v) => { if (v.aid) S.vs.set(v.aid, v); });
                rv();
            } else if (Rw.some((kw) => url.includes(kw))) {
                if (!Array.isArray(d.aweme_list)) return;
                d.aweme_list.map(fa).forEach((v) => { if (v.aid) S.vs.set(v.aid, v); });
                rv();
            } else if (Rs() && url.includes("/aweme/")) {
                const lst = d.aweme_list || d.media_list || d.history_list || [];
                if (!Array.isArray(lst)) return;
                lst.map((i) => { const aw = i.aweme_info || i.aweme || i; const v = fa(aw); v.itl = v.itl || nt(i.title); return v; }).forEach((v) => { if (v.aid) S.vs.set(v.aid, v); });
                rv();
            }
        };

        const si = (ui) => {
            if (!ui.uid) return;
            // S.cid 已被当前页面的第一个 profile 响应设置后，忽略任何其他 uid 的
            // profile 响应（过期响应、self profile API 等），防止清空已加载数据
            if (S.cid && S.cid !== ui.uid) return;
            S.cid = ui.uid;
            Array.from(S.vs.entries()).forEach(([k, v]) => { if (v.uid && v.uid !== ui.uid) S.vs.delete(k); });
            rv();
        };

        const hx = () => {
            const _o = XMLHttpRequest.prototype.open;
            const _s = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function (m, url) { this._u = nt(url); return _o.apply(this, arguments); };
            XMLHttpRequest.prototype.send = function (body) { this.addEventListener("load", function () { try { ha(this._u || "", nt(this.responseText)); } catch (_) {} }); return _s.apply(this, arguments); };
        };

        const hf = () => {
            if (typeof window.fetch !== "function") return;
            const _f = window.fetch;
            window.fetch = async function (...args) {
                const r = await _f.apply(this, args);
                const url = fu(args[0]);
                if (su(url)) { r.clone().text().then((t) => ha(url, t)).catch(() => ha(url, "")); }
                return r;
            };
        };

        // ── download helpers ──
        const fA = async (url) => { if (!url) throw new Error("下载地址为空"); const r = await fetch(url); if (!r.ok) throw new Error(`HTTP error! status: ${r.status}`); return new Uint8Array(await r.arrayBuffer()); };
        const fL = async (url) => { if (!url) throw new Error("下载地址为空"); const r = await fetch(url); if (!r.ok) throw new Error(`HTTP error! status: ${r.status}`); return r.blob(); };
        const fB = async (v) => { const imgs = (Array.isArray(v.imgs) ? v.imgs.filter(Boolean) : []).slice(0, 1); if (imgs.length === 0) throw new Error("无可用下载资源"); return fL(imgs[0]); };
        const dB = (blob, fn) => { const sn = (fn || "download").replace(/[\\/:*?"<>|]+/g, "_").trim() || "download"; const u = URL.createObjectURL(blob); const a = document.createElement("a"); a.href = u; a.download = sn; a.style.display = "none"; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 1000); };

        const uz = (zo, bn) => {
            if (!Object.prototype.hasOwnProperty.call(zo, bn)) return bn;
            const di = bn.lastIndexOf(".");
            const b = di > 0 ? bn.slice(0, di) : bn;
            const e = di > 0 ? bn.slice(di) : "";
            let n = 2;
            let c = `${b}_${n}${e}`;
            while (Object.prototype.hasOwnProperty.call(zo, c)) { n++; c = `${b}_${n}${e}`; }
            return c;
        };

        const zA = async (zo, label) => {
            if (typeof JSZip === "undefined") throw new Error("JSZip 未加载，无法打包文件");
            const zip = new JSZip();
            Object.entries(zo).forEach(([name, data]) => { zip.file(name, data); });
            return await zip.generateAsync({ type: "blob", compression: "STORE" }, (meta) => {
                tst(`${label} ${meta.percent.toFixed(0)}%`, true);
            });
        };

        const sZ = (zo, cs) => {
            const chunks = [];
            let cc = {}, sz = 0;
            Object.entries(zo).forEach(([k, v]) => { const es = v.length || v.byteLength || 0; if (sz > 0 && sz + es > cs) { chunks.push(cc); cc = {}; sz = 0; } cc[k] = v; sz += es; });
            if (Object.keys(cc).length > 0) chunks.push(cc);
            return chunks;
        };

        const zC = async (zo, an) => {
            const chunks = sZ(zo, ZS);
            const sa = sf(an, "未知作者", 40);
            for (let idx = 0; idx < chunks.length; idx++) {
                const cur = idx + 1;
                const pre = chunks.length > 1 ? `压缩 ${cur}/${chunks.length}` : "压缩中";
                tst(pre);
                try {
                    const zd = await zA(chunks[idx], pre);
                    const zn = chunks.length > 1 ? `${sa}_part${cur}.zip` : `${sa}.zip`;
                    dB(zd, zn);
                    if (chunks.length > 1 && cur < chunks.length) await sl(1000);
                } catch (e) { throw e; }
            }
            return chunks.length;
        };

        const rC = async (items, limit, wrk) => { let cur = 0; const ws = Array.from({ length: Math.min(limit, items.length) }, async () => { while (cur < items.length) { const i = cur++; await wrk(items[i], i); } }); await Promise.all(ws); };

        const sc = (items) => {
            if (items.length <= 1) return items;
            const ns = items.map((v) => gn(v));
            let pl = 0;
            for (let i = 0; i < ns[0].length; i++) { if (ns.some((n) => n[i] !== ns[0][i])) break; pl++; }
            const tr = ns[0].slice(0, pl).replace(/[_\-\s]+$/, "");
            if (tr.length < 3) return items;
            return items.map((v) => ({ ...v, _s: gn(v).slice(tr.length).replace(/^[_\-\s]+/, "") }));
        };

        const uP = (p) => { tst(`获取进度 ${p.completed}/${p.total}`, true); };

        const dS = async (v) => {
            try {
                tst("开始获取资源...");
                const blob = v.url ? await fL(v.url) : await fB(v);
                const ext = v.url ? gE(v.url, "mp4") : "zip";
                dB(blob, `${gn(v)}.${ext}`);
                tst("✔ 获取成功");
            } catch (_) { tst("✘ 获取失败，再试试"); }
        };

        const dZ = async (vids) => {
            const items = sc(vids);
            const failed = [];
            const zo = {};
            const tasks = [];
            items.forEach((v) => {
                if (v.url) tasks.push({ ty: "v", v, url: v.url });
                const imgs = Array.isArray(v.imgs) ? v.imgs.filter(Boolean) : [];
                imgs.forEach((img, i) => { tasks.push({ ty: "i", v, url: img, idx: i, total: imgs.length }); });
            });
            if (tasks.length === 0) { tst("✘ 未找到可用资源"); return; }
            const prog = { completed: 0, total: tasks.length };
            uP(prog);
            await rC(tasks, DC, async (tk) => {
                try {
                    const data = await fA(tk.url);
                    const nm = tk.ty === "v"
                        ? `${tk.v._s || gn(tk.v)}.${gE(tk.url, "mp4")}`
                        : `${tk.v._s || gn(tk.v)}/image_${String(tk.idx + 1).padStart(2, "0")}.${gE(tk.url, "jpg")}`;
                    zo[uz(zo, nm)] = data;
                } catch (_) { failed.push(tk.v.itl || tk.v.dsc || tk.v.aid); }
                prog.completed++; uP(prog);
            });
            if (Object.keys(zo).length === 0) { tst("✘ 全部获取失败"); return; }
            try {
                const chunks = await zC(zo, nt(vids[0]?.nick));
                if (failed.length) { tst(`${failed.length}个作品获取失败，其余已保存`); } else { const sfx = chunks > 1 ? `（共 ${chunks} 个压缩包）` : ""; tst(`✔ 全部保存完毕${sfx}`); }
            } catch (_) { tst("✘ 压缩异常，请重试"); }
        };

        const gs = () => Array.from(document.querySelectorAll(".dy-sel-cb:checked")).map((cb) => S.vs.get(cb.dataset.id)).filter(Boolean);

        const sd = (v) => { S.dl = v; us(); };

        const di = async () => {
            if (S.dl) return;
            const sel = gs();
            if (sel.length === 0) { alert("请选择要下载的内容。"); return; }
            sd(true);
            try { if (sel.length === 1 && sel[0].tp === T.v) { await dS(sel[0]); } else { await dZ(sel); } } finally { sd(false); }
        };

        // ── UI: inject checkboxes on page ──
        const icl = () => {
            if (!S.enabled) return;
            const links = document.querySelectorAll('a[href*="/video/"]:not([data-dy-checked]), a[href*="/note/"]:not([data-dy-checked]), a[href*="/article/"]:not([data-dy-checked])');
            links.forEach((link) => {
                link.setAttribute('data-dy-checked', '1');
                const m = /\/(video|note|article)\/(\d+)/.exec(link.getAttribute('href') || '');
                if (!m) return;
                const aid = m[2];
                if (!S.vs.has(aid)) return;
                const card = link.closest('li, [class*="waterfall_item"], [class*="waterfallItem"]');
                if (!card || card.querySelector('.dy-sel-cb')) return;
                const cs = getComputedStyle(card);
                if (cs.position === 'static') card.style.position = 'relative';
                // 卡片内链接阻止跳转
                link.addEventListener('click', (e) => {
                    if (!S.enabled) return;
                    e.preventDefault();
                    e.stopPropagation();
                }, true);
                const cb = document.createElement('input');
                cb.type = 'checkbox';
                cb.className = 'dy-sel-cb';
                cb.dataset.id = aid;
                cb.addEventListener('change', us);
                // checkbox 点击时阻止冒泡，避免 card 重复翻转
                cb.addEventListener('click', (e) => {
                    if (!S.enabled) return;
                    e.stopPropagation();
                });
                // 点击卡片区域时切换复选框
                card.addEventListener('click', (e) => {
                    if (!S.enabled) return;
                    // 如果点击的是 checkbox 本身，由浏览器原生处理，card 不干预
                    if (e.target === cb) return;
                    e.preventDefault();
                    e.stopPropagation();
                    cb.checked = !cb.checked;
                    cb.dispatchEvent(new Event('change', { bubbles: true }));
                }, true);
                card.appendChild(cb);
            });
            us();
        };

        const te = () => {
            S.enabled = !S.enabled;
            document.querySelectorAll('.dy-sel-cb').forEach((c) => c.remove());
            document.querySelectorAll('[data-dy-checked]').forEach((el) => el.removeAttribute('data-dy-checked'));
            us();
            icl();
        };

        const rv = () => { icl(); };

        const us = () => {
            const cbs = document.querySelectorAll('.dy-sel-cb');
            const cnt = Array.from(cbs).filter((c) => c.checked).length;
            const ce = document.getElementById('dy-count');
            const db = document.getElementById('dy-dl-btn');
            const sa = document.getElementById('dy-sel-all');
            const iv = document.getElementById('dy-invert');
            if (ce) ce.textContent = '已选 ' + cnt + ' 项';
            if (db) {
                db.disabled = S.dl || cnt === 0;
                if (cnt > 0) db.classList.add('dy-tb-primary');
                else db.classList.remove('dy-tb-primary');
            }
            if (sa) sa.disabled = S.dl || !S.enabled;
            if (iv) iv.disabled = S.dl || !S.enabled;
            cbs.forEach((c) => { c.disabled = S.dl; });
        };

        const hm = () => window.location.search.includes("modal_id");

        // 使工具栏可拖拽移动（整个菜单可拖动，移动超过阈值才算拖拽，不影响按钮点击）
        const initDrag = (el) => {
            el.addEventListener('pointerdown', function(e) {
                if (e.button !== 0) return;                    // 仅左键/触摸
                e.preventDefault();
                const startX = e.clientX, startY = e.clientY;
                const rect = el.getBoundingClientRect();
                const offX = e.clientX - rect.left;
                const offY = e.clientY - rect.top;
                let dragging = false;

                const onMove = (ev) => {
                    if (!dragging) {
                        // 移动未超过阈值视为点击，不启动拖拽
                        if (Math.abs(ev.clientX - startX) < 4 && Math.abs(ev.clientY - startY) < 4) return;
                        dragging = true;
                        // 从 transform 居中定位切换为显式 left/top，并清除 bottom 固定，否则元素会被上下两端钉住无法移动
                        el.style.left = rect.left + 'px';
                        el.style.top = rect.top + 'px';
                        el.style.bottom = 'auto';
                        el.style.transform = 'none';
                        el.style.margin = '0';
                    }
                    el.style.left = Math.max(0, Math.min(ev.clientX - offX, window.innerWidth - el.offsetWidth)) + 'px';
                    el.style.top = Math.max(0, Math.min(ev.clientY - offY, window.innerHeight - el.offsetHeight)) + 'px';
                };
                const onUp = () => {
                    window.removeEventListener('pointermove', onMove);
                    window.removeEventListener('pointerup', onUp);
                    window.removeEventListener('pointercancel', onUp);
                };
                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onUp);
                window.addEventListener('pointercancel', onUp);
            });
        };

        const itb = () => {
            if (!document.body) return;
            if (hm()) { const tb = document.getElementById('dy-toolbar'); if (tb) tb.remove(); const tgl = document.getElementById('dy-toolbar-toggle'); if (tgl) tgl.remove(); return; }
            const exist = document.getElementById('dy-toolbar');
            if (exist && exist.parentNode) return;
            const tb = exist || document.createElement('div');
            tb.id = 'dy-toolbar';
            tb.innerHTML = '<button id="dy-sel-all" class="dy-tb-btn" disabled>全选</button><button id="dy-invert" class="dy-tb-btn" disabled>反选</button><span id="dy-count" class="dy-tb-count">已选 0 项</span><button id="dy-dl-btn" class="dy-tb-btn" disabled>下载选中</button><button id="dy-collapse" class="dy-tb-btn dy-tb-primary" title="关闭工具栏"><span style="display:inline-block;">\u2715</span></button>';

            // 折叠状态下的展开按钮（默认折叠，点击展开工具栏）
            // 样式与工具栏一致，仅位置改为底部居中
            const tgl = document.createElement('button');
            tgl.id = 'dy-toolbar-toggle';
            tgl.innerHTML = '<span style="display:inline-block;transform:rotate(90deg);">\u276E</span>';
            tgl.title = '展开下载工具栏';
            tgl.style.cssText = 'position:fixed;z-index:2147483647;bottom:0px;left:50%;transform:translateX(-50%);box-sizing:border-box;width:55px;height:25px;padding:4px 10px;border-radius:8px 8px 0 0;background:rgba(0,0,0,0.6);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);color:#fff;border:1px solid #333;cursor:pointer;font-size:14px;line-height:1;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;display:flex;align-items:center;justify-content:center;transition:background 0.2s,height 0.2s;user-select:none;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
            tgl.addEventListener('mouseenter', () => { tgl.style.height = '30px'; tgl.style.background = 'rgba(0,0,0,0.75)'; });
            tgl.addEventListener('mouseleave', () => { tgl.style.height = '25px'; tgl.style.background = 'rgba(0,0,0,0.6)'; });
            tgl.addEventListener('click', () => {
                if (!S.enabled) te(); // 展开时自动启用下载
                tb.style.display = 'flex';
                tgl.style.display = 'none';
            });
            if (!tb.parentNode) document.body.appendChild(tb);
            document.body.appendChild(tgl);
            initDrag(tb);
            document.getElementById('dy-sel-all').addEventListener('click', () => { document.querySelectorAll('.dy-sel-cb').forEach((c) => { c.checked = true; }); us(); });
            document.getElementById('dy-invert').addEventListener('click', () => { document.querySelectorAll('.dy-sel-cb').forEach((c) => { c.checked = !c.checked; }); us(); });
            document.getElementById('dy-dl-btn').addEventListener('click', di);
            document.getElementById('dy-collapse').addEventListener('click', () => {
                if (S.enabled) te(); // 收起时自动停用下载
                tb.style.display = 'none';
                tgl.style.display = 'flex';
            });
        };

        const rB = (cb) => { if (document.body) { cb(); return; } document.addEventListener("DOMContentLoaded", cb, { once: true }); };

        // ── home page init (only when on /user/ page) ──

        if (!up()) return;

        const nu = () => { const u = new URL(window.location.href); u.searchParams.delete("modal_id"); return u.pathname + u.search; };
        let _lp = nu();
        const ot = () => {
            const cur = nu();
            if (cur !== _lp) {
                _lp = cur;
                S.ver++;  // bump version so in-flight stale responses are discarded
                S.cid = "";  // reset current user id (previously missing, allowing stale uid to persist)
                S.vs.clear(); S.enabled = false;
                document.querySelectorAll('.dy-sel-cb').forEach((c) => c.remove());
                document.querySelectorAll('[data-dy-checked]').forEach((el) => el.removeAttribute('data-dy-checked'));
                us();
            }
            // 离开 /user/ 页面时移除工具栏（SPA 路由切换不会销毁 body 上的 DOM）
            if (!up()) {
                const tb = document.getElementById('dy-toolbar');
                if (tb) tb.remove();
                const tgl = document.getElementById('dy-toolbar-toggle');
                if (tgl) tgl.remove();
                return;
            }
            // 立即根据 modal_id 状态显示/隐藏工具栏
            const tb = document.getElementById('dy-toolbar');
            if (hm()) { if (tb) tb.remove(); const tgl = document.getElementById('dy-toolbar-toggle'); if (tgl) tgl.remove(); }
            else { if (!tb) itb(); }
        };
        const opH = history.pushState;
        const rpH = history.replaceState;
        history.pushState = function () { opH.apply(this, arguments); ot(); };
        history.replaceState = function () { rpH.apply(this, arguments); ot(); };
        window.addEventListener("popstate", ot);
        setInterval(ot, 500);
        setInterval(() => { itb(); icl(); }, 600);

        GM_addStyle(`
            .dy-sel-cb {
                appearance: none;
                position: absolute;
                top: 8px;
                left: 8px;
                z-index: 99;
                width: 20px;
                height: 20px;
                border: 2px solid rgba(255,255,255,0.85);
                border-radius: 5px;
                cursor: pointer;
                background: rgba(0,0,0,0.35);
                transition: all .15s;
                margin: 0;
            }
            .dy-sel-cb:checked {
                background: #fe2c55;
                border-color: #fe2c55;
            }
            .dy-sel-cb:checked::after {
                content: "";
                position: absolute;
                left: 5px;
                top: 2px;
                width: 5px;
                height: 9px;
                border: solid #fff;
                border-width: 0 2px 2px 0;
                transform: rotate(45deg);
            }
            #dy-toolbar {
                position: fixed;
                bottom: 20px;
                left: 50%;
                transform: translateX(-50%);
                z-index: 2147483646;
                display: none; /* 默认折叠 */
                align-items: center;
                gap: 10px;
                padding: 10px 18px;
                background: rgba(0,0,0,0.6);
                backdrop-filter: blur(16px);
                border-radius: 20px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.3);
                border: 1px solid #333;
                cursor: grab;
                user-select: none;
            }
            #dy-toolbar:active { cursor: grabbing; }
            .dy-tb-btn {
                height: 32px;
                padding: 0 14px;
                border: none;
                border-radius: 16px;
                background: rgba(255,255,255,0.18);
                color: #fff;
                font-size: 13px;
                font-weight: 500;
                cursor: pointer;
                white-space: nowrap;
                transition: background .15s;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            .dy-tb-btn:hover { background: rgba(255,255,255,0.28); }
            .dy-tb-btn:disabled { opacity: 0.35; cursor: not-allowed; }
            .dy-tb-on { background: #fe2c55; }
            .dy-tb-on:hover { background: #e0264d; }
            .dy-tb-primary { background: #fe2c55; }
            .dy-tb-primary:hover:not(:disabled) { background: #e0264d; }
            .dy-tb-count {
                color: rgba(255,255,255,0.7);
                font-size: 12px;
                font-weight: 500;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                white-space: nowrap;
                min-width: 60px;
                text-align: center;
            }
            #dy-collapse {
                width: 36px;
                padding: 0;
            }
        `);

        hx();
        hf();
        rB(itb);

    })();


    // ═══════════════════════════════════════════
    //  Module B: 视频/图文/文章增强
    // ═══════════════════════════════════════════

    // 创建预览图片元素
    const preview = elements.createAs("img", {
        id: "preview",
        style: `
            position: absolute;
            z-index: 2000;
            max-width: 60vw;
            max-height: 60vh;
            border: 1px solid #fff;
            border-radius: 4px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.5);
            display: none;
            z-index: 1000000000;
        `
    }, document.body);


    // 添加点击事件监听器
    preview.addEventListener('click', function() {
        this.style.display = 'none';
    });

    // 点击网页其他区域时关闭缩略图
    document.addEventListener('click', function(e) {
        if (e.target.closest('#preview') || e.target.closest('#dy-thumbnail-btn')) {
            return;
        }
        preview.style.display = 'none';
    });


    // 添加CSS样式
    elements.createAs('style', {
        textContent: `
            .dy-icon-btn {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                width: 28px;
                height: 28px;
                border-radius: 50%;
                cursor: pointer;
                transition: all 0.3s ease;
                background-color: #444;
                backdrop-filter: blur(4px);
                box-shadow: 0 2px 8px rgba(0,0,0,0.1);
                text-decoration: none;
            }

            .dy-icon-btn svg {
                width: 14px;
                height: 14px;
                fill: white;
            }

            .dy-icon-btn img {
                width: 14px;
                height: 14px;
                filter: brightness(0) invert(1);
            }

            .dy-icon-btn:hover {
                transform: scale(1.1);
            }
        `
    }, document.head);

    // 抖音浏览助手主体
    const douyinViewer = {
        buttonCheckInterval: null,

        // 检查是否在有视频的页面
        isVideoPage() {
            // 抖音绝大部分页面都有视频
            return document.querySelector('video') !== null;
        },

        // 检查是否在图文页面
        isImageTextPage() {
            // URL 检测
            if (window.location.pathname.includes('/note/')) return true;
            // DOM 检测：查找图文专用的容器元素
            return document.querySelector('[data-e2e*="note"], .note-item, .note-detail, [class*="note-item"]') !== null;
        },

        // 检查是否在文章页面
        isArticlePage() {
            return window.location.pathname.includes('/article/');
        },

        // 获取当前视频的 aweme_id
        getAwemeId(targetElement) {
            // 1. 从目标元素向上查找 (针对 Feed 流)
            if (targetElement) {
                const container = targetElement.closest('[data-e2e="video-item"], .video-item, xg-video-container');
                if (container) {
                    const link = container.querySelector('a[href*="/video/"]');
                    if (link) {
                        const match = link.getAttribute('href').match(/video\/(\d+)/);
                        if (match && match[1]) return match[1];
                    }
                }
            }

            // 2. 从 URL pathname 中提取视频ID
            let match = window.location.pathname.match(/video\/(\d+)/);
            if (match && match[1]) return match[1];

            // 2.5 从 URL pathname 中提取图文ID
            match = window.location.pathname.match(/note\/(\d+)/);
            if (match && match[1]) return match[1];

            // 3. 从 URL search params 中提取
            match = window.location.search.match(/modal_id=(\d+)/);
            if (match && match[1]) return match[1];

            // 4. 从当前播放的 video 父容器中提取 (针对 Feed 流)
            const activeVideo = document.querySelector('video');
            if (activeVideo) {
                const container = activeVideo.closest('[data-e2e="video-item"]');
                if (container) {
                    const link = container.querySelector('a[href*="/video/"]');
                    if (link) {
                        match = link.getAttribute('href').match(/video\/(\d+)/);
                        if (match && match[1]) return match[1];
                    }
                }
            }
            return null;
        },

        // 获取抖音缩略图URL
        getThumbnailUrl(targetElement) {
            return new Promise((resolve) => {
                const awemeId = this.getAwemeId(targetElement);
                if (!awemeId) {
                    // 后备方案
                    const activeVideo = document.querySelector('video');
                    if (activeVideo && activeVideo.poster && activeVideo.poster.trim() !== '') {
                        resolve(activeVideo.poster);
                        return;
                    }
                    resolve(null);
                    return;
                }

                GM_xmlhttpRequest({
                    method: 'GET',
                    url: `https://www.iesdouyin.com/share/video/${awemeId}/`,
                    headers: {
                        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1'
                    },
                    onload: (response) => {
                        try {
                            const match = response.responseText.match(/window\._ROUTER_DATA\s*=\s*(\{.*?\});?<\/script>/);
                            if (match && match[1]) {
                                const data = JSON.parse(match[1]);
                                const loaderKey = Object.keys(data.loaderData || {}).find(k => k.includes('_(id)/page'));
                                if (loaderKey) {
                                    const item = data.loaderData[loaderKey].videoInfoRes.item_list[0];
                                    if (item) {
                                        if (item.video && item.video.cover && item.video.cover.url_list) {
                                            resolve(item.video.cover.url_list[0]);
                                            return;
                                        }
                                        if (item.images && item.images.length > 0 && item.images[0].url_list) {
                                            resolve(item.images[0].url_list[0]);
                                            return;
                                        }
                                    }
                                }
                            }
                        } catch (e) {
                            console.error("解析抖音封面API失败:", e);
                        }

                        // 失败后的后备方案
                        const activeVideo = document.querySelector('video');
                        if (activeVideo && activeVideo.poster && activeVideo.poster.trim() !== '') {
                            resolve(activeVideo.poster);
                        } else {
                            resolve(null);
                        }
                    },
                    onerror: () => {
                        const activeVideo = document.querySelector('video');
                        if (activeVideo && activeVideo.poster && activeVideo.poster.trim() !== '') {
                            resolve(activeVideo.poster);
                        } else {
                            resolve(null);
                        }
                    }
                });
            });
        },

        // 获取图文的所有图片URL
        getNoteImageUrls(targetElement) {
            return new Promise((resolve) => {
                const awemeId = this.getAwemeId(targetElement);
                if (!awemeId) {
                    resolve([]);
                    return;
                }

                GM_xmlhttpRequest({
                    method: 'GET',
                    url: `https://www.iesdouyin.com/share/video/${awemeId}/`,
                    headers: {
                        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1'
                    },
                    onload: (response) => {
                        try {
                            const match = response.responseText.match(/window\._ROUTER_DATA\s*=\s*(\{.*?\});?<\/script>/);
                            if (match && match[1]) {
                                const data = JSON.parse(match[1]);
                                const loaderKey = Object.keys(data.loaderData || {}).find(k => k.includes('_(id)/page'));
                                if (loaderKey) {
                                    const item = data.loaderData[loaderKey].videoInfoRes.item_list[0];
                                    if (item && item.images && item.images.length > 0) {
                                        const urls = item.images.map(img => img.url_list[0]);
                                        resolve(urls);
                                        return;
                                    }
                                }
                            }
                        } catch (e) {
                            console.error("解析图文API失败:", e);
                        }
                        resolve([]);
                    },
                    onerror: () => {
                        resolve([]);
                    }
                });
            });
        },

        // 获取图片后弹出选择界面（或回退到视频下载）
        async batchDownloadImages(event) {
            const target = event ? event.currentTarget : null;
            const imageUrls = await this.getNoteImageUrls(target);
            if (imageUrls.length === 0) {
                // 不是图文内容，回退到视频下载
                this.downloadVideo(event);
                return;
            }
            // 弹出选择界面，让用户手动选择要下载的图片
            this.showImageSelector(imageUrls);
        },

        // 获取播放器中的活跃媒体对象
        getActiveMedia() {
            const player = window.player || (typeof unsafeWindow !== 'undefined' && unsafeWindow.player);
            return player?.config?.awemeInfo || null;
        },

        // 文件命名逻辑
        _composeFilename(media, prefix = '') {
            const { authorInfo: { nickname } = {}, desc, textExtra } = media;
            const hashtags = (textExtra || []).map((t) => '#' + t.hashtagName).filter(Boolean).join('_');
            let cleanDesc = (desc || '').trim();
            (textExtra || []).forEach((t) => { cleanDesc = cleanDesc.replace(new RegExp('#' + t.hashtagName + '\\s*', 'g'), ''); });
            cleanDesc = cleanDesc.replace(/[#\/\?<>\\:\*\|":]/g, '');
            let name = (prefix ? prefix + '_' : '') + [nickname, hashtags, cleanDesc].filter(Boolean).join('_');
            if (name.length > 64) name = name.slice(0, 64);
            return name.replace(/\./g, '_');
        },

        // 通过 fetch 下载文件
        async _downloadViaFetch(url, filename) {
            try {
                const res = await fetch(url);
                if (!res.ok) throw new Error('HTTP ' + res.status);
                const blob = await res.blob();
                const a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = filename;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(a.href);
                return true;
            } catch (e) {
                console.error('下载失败:', e);
                return false;
            }
        },

        // 下载视频
        async downloadVideo(event) {
            const media = this.getActiveMedia();
            if (!media) {
                this.showToast('未检测到播放中的视频');
                return;
            }

            const video = media.video;
            const links = [];
            if (video) {
                if (video.playApi) links.push(video.playApi);
                if (video.playApiH265) links.push(video.playApiH265);
                if (video.playAddr) {
                    (Array.isArray(video.playAddr) ? video.playAddr : [video.playAddr]).forEach(a => {
                        if (a.src) links.push(a.src);
                    });
                }
                if (video.bitRateList) {
                    video.bitRateList.filter(b => b.format !== 'dash').forEach(b => {
                        if (b.playApi) links.push(b.playApi);
                        if (Array.isArray(b.playAddr)) b.playAddr.forEach(a => { if (a.src) links.push(a.src); });
                    });
                }
            }

            const uniqueLinks = [...new Set(links.filter(Boolean))];
            if (uniqueLinks.length === 0) {
                this.showToast('未找到可下载的视频链接');
                return;
            }

            this.showToast('正在下载视频...');
            const name = this._composeFilename(media) + '.mp4';

            for (const url of uniqueLinks) {
                const ok = await this._downloadViaFetch(url, name);
                if (ok) {
                    this.showToast('视频下载完成');
                    return;
                }
            }
            this.showToast('视频下载失败');
        },

        // 下载背景音乐
        async downloadMusic(event) {
            const media = this.getActiveMedia();
            if (!media) {
                this.showToast('未检测到播放中的视频');
                return;
            }

            const music = media.music;
            if (!music) {
                this.showToast('当前视频无背景音乐');
                return;
            }

            const url = music.playUrl?.urlList?.[0];
            if (!url) {
                this.showToast('背景音乐链接无效');
                return;
            }

            this.showToast('正在下载背景音乐...');
            const name = this._composeFilename(media) + '.mp3';

            const ok = await this._downloadViaFetch(url, name);
            if (ok) {
                this.showToast('背景音乐下载完成');
                return;
            }
            // 尝试备用链接
            const fallbacks = music.playUrl?.urlList?.slice(1) || [];
            for (const fbUrl of fallbacks) {
                const fbOk = await this._downloadViaFetch(fbUrl, name);
                if (fbOk) {
                    this.showToast('背景音乐下载完成');
                    return;
                }
            }
            this.showToast('背景音乐下载失败');
        },

        // 从页面标题元素提取文件名
        extractName() {
            const titleEl = document.querySelector('.account-name-text');
            let name = (titleEl && titleEl.textContent) ? titleEl.textContent.trim() : (document.title || '');
            // 去除抖音后缀
            name = name.replace(/[\s\-–—|]*抖音[\s\-–—|]*/g, '');
            name = name.replace(/[\s\-–—|]*Douyin[\s\-–—|]*/gi, '');
            // 去除非法文件名字符
            name = name.replace(/[\\\/:*?"<>|]/g, '');
            // 去除首尾空白和多余空格
            name = name.trim().replace(/\s+/g, ' ');
            // 截断过长名称
            if (name.length > 64) {
                name = name.substring(0, 64);
            }
            // 兜底
            if (!name) {
                name = 'douyin_' + Date.now();
            }
            return name;
        },

        // 下载选中的图片（ZIP 打包）
        downloadSelectedImages(imageUrls) {
            const self = this;
            const total = imageUrls.length;
            if (total === 0) return;

            const baseName = this.extractName();

            self.showToast(`正在下载并打包 ${total} 张图片...`);

            // 并行下载所有图片
            const downloadPromises = imageUrls.map((url, index) => {
                return new Promise((resolve) => {
                    GM_xmlhttpRequest({
                        method: 'GET',
                        url: url,
                        responseType: 'blob',
                        headers: {
                            'Referer': 'https://www.douyin.com/',
                            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1'
                        },
                        onload: (response) => {
                            const blob = response.response;
                            if (blob && blob.size > 0) {
                                resolve({ blob, index, name: `${baseName}_${String(index + 1).padStart(2, '0')}.jpg` });
                            } else {
                                console.error('图片下载失败(空响应):', url);
                                resolve(null);
                            }
                        },
                        onerror: (err) => {
                            console.error('图片下载失败:', url, err);
                            resolve(null);
                        }
                    });
                });
            });

            Promise.all(downloadPromises).then(async (results) => {
                const validResults = results.filter(r => r !== null);
                if (validResults.length === 0) {
                    self.showToast('所有图片下载失败');
                    return;
                }

                // 单张图片直接下载
                if (validResults.length === 1) {
                    const item = validResults[0];
                    const blobUrl = URL.createObjectURL(item.blob);
                    const a = document.createElement('a');
                    a.href = blobUrl;
                    a.download = item.name;
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
                    self.showToast('下载完成');
                    return;
                }

                // 多张图片打包成 ZIP
                try {
                    if (typeof JSZip === 'undefined') {
                        throw new Error('JSZip not loaded');
                    }
                    const zip = new JSZip();
                    validResults.forEach((item) => {
                        zip.file(item.name, item.blob);
                    });
                    const content = await zip.generateAsync({ type: 'blob', compression: 'STORE' });
                    const blobUrl = URL.createObjectURL(content);
                    const a = document.createElement('a');
                    a.href = blobUrl;
                    a.download = `${baseName}.zip`;
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    setTimeout(() => URL.revokeObjectURL(blobUrl), 2000);
                    self.showToast('ZIP 打包下载完成');
                } catch (e) {
                    console.error('ZIP 打包失败，改为逐个下载:', e);
                    validResults.forEach((item, i) => {
                        setTimeout(() => {
                            const blobUrl = URL.createObjectURL(item.blob);
                            const a = document.createElement('a');
                            a.href = blobUrl;
                            a.download = item.name;
                            document.body.appendChild(a);
                            a.click();
                            document.body.removeChild(a);
                            setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
                        }, i * 400);
                    });
                }
            });
        },

        // 查找文章正文容器（类名是混淆的且会变动，使用已知类名 + 结构回退）
        getArticleContentEl() {
            const selectors = ['.afVneZqM', '.H9UzUzLP'];
            for (const sel of selectors) {
                const el = document.querySelector(sel);
                if (el) return el;
            }
            // 结构回退：在 leftContainer 中找直接 <p> 子元素最多的容器
            const left = document.querySelector('.leftContainer');
            if (left) {
                let best = null, bestCount = 0;
                left.querySelectorAll('div').forEach(div => {
                    const cnt = div.querySelectorAll(':scope > p').length;
                    if (cnt > bestCount) { bestCount = cnt; best = div; }
                });
                if (best && bestCount >= 3) return best;
            }
            return null;
        },

        // 查找文章标题元素
        getArticleTitleEl() {
            const selectors = ['.PGCkj7_z', '.ZuAUZjxr'];
            for (const sel of selectors) {
                const el = document.querySelector(sel);
                if (el) return el;
            }
            // 结构回退：leftContainer 中第一个有文字且无子元素的 div
            const left = document.querySelector('.leftContainer');
            if (left) {
                const divs = left.querySelectorAll('div');
                for (const div of divs) {
                    const text = (div.innerText || '').trim();
                    if (div.children.length === 0 && text.length >= 5 && text.length <= 100) {
                        return div;
                    }
                }
            }
            return null;
        },

        // 获取文章正文中的所有图片URL
        getArticleImageUrls() {
            const contentEl = this.getArticleContentEl();
            if (!contentEl) return [];
            const imgs = contentEl.querySelectorAll('img');
            return Array.from(imgs)
                .map(img => img.src || img.getAttribute('data-src') || '')
                .filter(url => url && (url.startsWith('http') || url.startsWith('//')))
                .map(url => url.startsWith('//') ? 'https:' + url : url);
        },

        // 文章页面 - 查看正文图片并下载
        viewArticleImages(event) {
            event && event.preventDefault && event.preventDefault();
            const imageUrls = this.getArticleImageUrls();
            if (imageUrls.length === 0) {
                this.showToast('文章正文中没有找到图片');
                return;
            }
            this.showImageSelector(imageUrls);
        },

        // HTML 转 Markdown
        htmlToMarkdown(element) {
            const getTextContent = (node) => {
                let text = '';
                Array.from(node.childNodes).forEach(child => {
                    if (child.nodeType === 3) {
                        text += child.textContent.replace(/[^\S\n]+/g, ' ');
                    } else if (child.nodeType === 1) {
                        const nn = child.nodeName.toLowerCase();
                        if (nn !== 'script' && nn !== 'style') {
                            text += getTextContent(child);
                        }
                    }
                });
                return text.trim();
            };

            const processChildNodes = (node) => {
                let content = '';
                Array.from(node.childNodes).forEach(child => {
                    content += processNode(child);
                });
                return content;
            };

            const processNode = (node) => {
                if (node.nodeType === 3) {
                    return node.textContent.replace(/[^\S\n]+/g, ' ');
                }
                if (node.nodeType !== 1) return '';
                const nodeName = node.nodeName.toLowerCase();
                if (/^h[1-6]$/.test(nodeName)) {
                    const level = parseInt(nodeName.charAt(1));
                    return '#'.repeat(level) + ' ' + getTextContent(node) + '\n\n';
                } else if (nodeName === 'p') {
                    return processChildNodes(node) + '\n\n';
                } else if (nodeName === 'br') {
                    return '\n';
                } else if (nodeName === 'hr') {
                    return '---\n\n';
                } else if (nodeName === 'ul') {
                    let listContent = '';
                    Array.from(node.children).forEach(item => {
                        if (item.nodeName.toLowerCase() === 'li') {
                            listContent += '- ' + processChildNodes(item) + '\n';
                        }
                    });
                    return listContent + '\n';
                } else if (nodeName === 'ol') {
                    let listContent = '';
                    Array.from(node.children).forEach((item, index) => {
                        if (item.nodeName.toLowerCase() === 'li') {
                            listContent += (index + 1) + '. ' + processChildNodes(item) + '\n';
                        }
                    });
                    return listContent + '\n';
                } else if (nodeName === 'blockquote') {
                    const text = processChildNodes(node);
                    return '> ' + text.replace(/\n/g, '\n> ') + '\n\n';
                } else if (nodeName === 'pre') {
                    return '```\n' + node.textContent + '\n```\n\n';
                } else if (nodeName === 'code') {
                    return '`' + node.textContent + '`';
                } else if (nodeName === 'strong' || nodeName === 'b') {
                    return '**' + processChildNodes(node) + '**';
                } else if (nodeName === 'em' || nodeName === 'i') {
                    return '*' + processChildNodes(node) + '*';
                } else if (nodeName === 'a') {
                    const href = node.getAttribute('href') || '';
                    return '[' + processChildNodes(node) + '](' + href + ')';
                } else if (nodeName === 'img') {
                    const src = node.getAttribute('src') || node.getAttribute('data-src') || '';
                    const alt = node.getAttribute('alt') || '';
                    const fullSrc = src.startsWith('//') ? 'https:' + src : src;
                    return '![' + alt + '](' + fullSrc + ')';
                } else if (nodeName === 'table') {
                    let tableContent = '';
                    const rows = node.querySelectorAll('tr');
                    if (rows.length > 0) {
                        const headerCells = rows[0].querySelectorAll('th,td');
                        let headerContent = '|';
                        let separatorRow = '|';
                        headerCells.forEach(cell => {
                            headerContent += ' ' + getTextContent(cell) + ' |';
                            separatorRow += ' --- |';
                        });
                        tableContent += headerContent + '\n' + separatorRow + '\n';
                        for (let i = 1; i < rows.length; i++) {
                            const cells = rows[i].querySelectorAll('td');
                            let rowContent = '|';
                            cells.forEach(cell => {
                                rowContent += ' ' + getTextContent(cell) + ' |';
                            });
                            tableContent += rowContent + '\n';
                        }
                    }
                    return tableContent + '\n';
                } else {
                    return processChildNodes(node);
                }
            };

            return processNode(element);
        },

        // 文章页面 - 复制全文（Markdown 格式）
        copyArticleText(event) {
            event && event.preventDefault && event.preventDefault();
            const contentEl = this.getArticleContentEl();
            if (!contentEl) {
                this.showToast('未找到文章正文');
                return;
            }
            const markdown = this.htmlToMarkdown(contentEl);
            if (!markdown.trim()) {
                this.showToast('文章正文为空');
                return;
            }
            navigator.clipboard.writeText(markdown).then(() => {
                this.showToast('已复制全文（Markdown）');
            }).catch(() => {
                this.showToast('复制失败，请重试');
            });
        },

        // 文章页面 - 下载全文为 MD 文件
        downloadArticleMd(event) {
            event && event.preventDefault && event.preventDefault();
            const titleEl = this.getArticleTitleEl();
            const contentEl = this.getArticleContentEl();
            if (!contentEl) {
                this.showToast('未找到文章正文');
                return;
            }
            const title = titleEl ? titleEl.innerText.trim() : (document.title || '文章');

            // 日期格式化
            const d = new Date();
            const pad = n => String(n).padStart(2, '0');
            const dateStr = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}-${pad(d.getHours())}:${pad(d.getMinutes())}`;

            // 元数据
            const metadata = '```\n' + title + '\n' + window.location.href + '\n' + dateStr + '\n```\n\n';

            // HTML 转 Markdown
            const markdown = this.htmlToMarkdown(contentEl);
            const fullMarkdown = metadata + markdown;

            // 下载文件
            const safeTitle = document.title.replace(/[\\/:*?"<>|]/g, '_') || 'douyin_article';
            const blob = new Blob([fullMarkdown], { type: 'text/markdown' });
            const blobUrl = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = blobUrl;
            a.download = safeTitle + '.md';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(() => URL.revokeObjectURL(blobUrl), 2000);
            this.showToast('已下载 MD 文件');
        },

        // 弹出图片选择界面
        showImageSelector(imageUrls) {
            const existing = document.getElementById('dy-image-selector');
            if (existing) existing.remove();

            const self = this;

            const overlay = elements.createAs('div', {
                id: 'dy-image-selector',
                style: `
                    position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                    background: rgba(0,0,0,0.6); z-index: 1000000001;
                    display: flex; align-items: center; justify-content: center;
                `
            }, document.body);

            overlay.addEventListener('click', function(e) {
                if (e.target === overlay) overlay.remove();
            });

            const container = elements.createAs('div', {
                style: `
                    background: #fff; border-radius: 12px;
                    width: 90vw; max-width: 560px; max-height: 80vh;
                    display: flex; flex-direction: column;
                    box-shadow: 0 8px 32px rgba(0,0,0,0.3);
                `
            }, overlay);

            // 头部
            const header = elements.createAs('div', {
                style: `
                    display: flex; align-items: center; justify-content: space-between;
                    padding: 14px 20px; border-bottom: 1px solid #eee; flex-shrink: 0;
                `
            }, container);

            elements.createAs('span', {
                textContent: '选择要下载的图片（共 ' + imageUrls.length + ' 张）',
                style: 'font-size: 15px; font-weight: bold; color: #333;'
            }, header);

            elements.createAs('span', {
                textContent: '\u2715',
                style: 'font-size: 20px; cursor: pointer; color: #999; padding: 0 4px; line-height: 1;',
                onclick: () => overlay.remove()
            }, header);

            // 图片网格
            const listContainer = elements.createAs('div', {
                style: `
                    flex: 1; overflow-y: auto; padding: 14px 20px;
                    min-height: 100px;
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
                    gap: 12px;
                    align-content: start;
                `
            }, container);

            const checkboxes = [];

            imageUrls.forEach((url, i) => {
                const card = elements.createAs('div', {
                    style: `
                        position: relative; border-radius: 8px; overflow: hidden;
                        cursor: pointer; border: 2px solid #fe2c55;
                        background: #fff; transition: border-color 0.2s;
                        display: flex; flex-direction: column;
                    `
                }, listContainer);

                const imgWrap = elements.createAs('div', {
                    style: `
                        position: relative; width: 100%; aspect-ratio: 1;
                        overflow: hidden;
                    `
                }, card);

                elements.createAs('img', {
                    src: url,
                    style: `
                        width: 100%; height: 100%; object-fit: cover; display: block;
                    `
                }, imgWrap);

                const cb = elements.createAs('input', {
                    type: 'checkbox',
                    checked: true,
                    style: `
                        position: absolute; top: 6px; right: 6px;
                        width: 20px; height: 20px; cursor: pointer;
                        accent-color: #fe2c55; z-index: 2; margin: 0;
                    `
                }, imgWrap);
                checkboxes.push(cb);

                elements.createAs('span', {
                    textContent: '图片 ' + (i + 1),
                    style: `
                        display: block; text-align: center; padding: 6px 4px;
                        font-size: 12px; color: #666; user-select: none; flex-shrink: 0;
                    `
                }, card);

                function updateSelectionStyle() {
                    card.style.borderColor = cb.checked ? '#fe2c55' : '#ddd';
                }

                card.addEventListener('click', function(e) {
                    if (e.target !== cb) {
                        cb.checked = !cb.checked;
                        updateSelectionStyle();
                        updateDownloadBtn();
                    }
                });

                cb.addEventListener('change', function() {
                    updateSelectionStyle();
                    updateDownloadBtn();
                });
            });

            // 底部工具栏
            const footer = elements.createAs('div', {
                style: `
                    display: flex; align-items: center; justify-content: space-between;
                    padding: 12px 20px; border-top: 1px solid #eee; gap: 10px; flex-shrink: 0;
                `
            }, container);

            const btnBase = 'padding: 7px 15px; border: none; border-radius: 6px; cursor: pointer; font-size: 13px; font-weight: bold; transition: opacity 0.2s;';

            const leftGroup = elements.createAs('div', {
                style: 'display: flex; gap: 8px;'
            }, footer);

            elements.createAs('button', {
                textContent: '全选',
                style: btnBase + 'background: #f0f0f0; color: #333;',
                onclick: () => {
                    checkboxes.forEach(cb => { cb.checked = true; });
                    updateDownloadBtn();
                }
            }, leftGroup);

            elements.createAs('button', {
                textContent: '反选',
                style: btnBase + 'background: #f0f0f0; color: #333;',
                onclick: () => {
                    checkboxes.forEach(cb => { cb.checked = !cb.checked; });
                    updateDownloadBtn();
                }
            }, leftGroup);

            const rightGroup = elements.createAs('div', {
                style: 'display: flex; gap: 8px;'
            }, footer);

            elements.createAs('button', {
                textContent: '取消',
                style: btnBase + 'background: #f0f0f0; color: #333;',
                onclick: () => overlay.remove()
            }, rightGroup);

            const downloadBtn = elements.createAs('button', {
                textContent: '下载选中 (' + imageUrls.length + ')',
                style: btnBase + 'background: #fe2c55; color: #fff;',
                onclick: () => {
                    const selected = imageUrls.filter((_, idx) => checkboxes[idx].checked);
                    if (selected.length === 0) {
                        self.showToast('请至少选择一张图片');
                        return;
                    }
                    overlay.remove();
                    self.downloadSelectedImages(selected);
                }
            }, rightGroup);

            function updateDownloadBtn() {
                const count = checkboxes.filter(cb => cb.checked).length;
                downloadBtn.textContent = '下载选中 (' + count + ')';
                if (count === 0) {
                    downloadBtn.disabled = true;
                    downloadBtn.style.opacity = '0.45';
                } else {
                    downloadBtn.disabled = false;
                    downloadBtn.style.opacity = '1';
                }
            }
        },

        // 显示提示消息
        showToast(message) {
            const toast = elements.createAs("div", {
                style: `
                    position: fixed;
                    top: 5%;
                    left: 50%;
                    transform: translateX(-50%);
                    background: #3F7FEA;
                    color: #fff;
                    padding: 16px 18px;
                    min-height: 20px;
                    min-width: 180px;
                    line-height: 1.2;
                    border-radius: 13px;
                    font-size: 14px;
                    font-family: sans-serif;
                    z-index: 2147483647;
                    pointer-events: none;
                    opacity: 0;
                    transition: opacity 0.25s ease;
                    box-shadow: 0 2px 8px rgba(0,122,255,0.25), 0 0 0 0.5px rgba(0,122,255,0.1);
                    box-sizing: border-box;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                `,
                textContent: message
            }, document.body);

            // 触发显示
            requestAnimationFrame(() => { toast.style.opacity = '1'; });

            setTimeout(() => {
                toast.style.opacity = '0';
                setTimeout(() => {
                    if (document.body.contains(toast)) document.body.removeChild(toast);
                }, 300);
            }, 1000);
        },

        // 注入按钮到指定目标元素后
        injectButtonsTo(targetEl) {
            // 如果该元素后已经添加了按钮，或者父元素已经包含了按钮，则跳过
            if (targetEl.querySelector('.dy-helper-buttons') || targetEl.parentNode?.querySelector('.dy-helper-buttons') || targetEl.closest('.video-info-detail, [data-e2e="video-item"], .video-item')?.querySelector('.dy-helper-buttons')) {
                return;
            }

            // 按容器判断是否为图文/笔记
            const isNote = targetEl.closest('[data-e2e="note-item"], .note-item, .note-detail') !== null;

            // 创建按钮容器
            const buttonContainer = elements.createAs('span', {
                className: 'dy-helper-buttons',
                style: `
                    display: inline-flex;
                    flex-direction: row;
                    gap: 10px;
                    vertical-align: middle;
                    margin-left: 15px;
                    z-index: 99999;
                `
            });

            // 将按钮容器附加到目标容器的末尾（或其父级内部，取决于目标类型）
            if (targetEl.tagName.toLowerCase() === 'span' || targetEl.tagName.toLowerCase() === 'div' || targetEl.tagName.toLowerCase() === 'h1') {
                 targetEl.appendChild(buttonContainer);
            } else {
                 targetEl.parentNode.insertBefore(buttonContainer, targetEl.nextSibling);
            }

            // 创建缩略图按钮（已注释，改用"获取文案"按钮）
            // elements.createAs('a', {
            //     id: 'dy-thumbnail-btn',
            //     href: 'javascript:void(0);',
            //     className: 'dy-icon-btn',
            //     title: '点击查看/隐藏视频封面',
            //     innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M6.002 5.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0z"/><path d="M2.002 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2h-12zm12 1a1 1 0 0 1 1 1v6.5l-3.777-1.947a.5.5 0 0 0-.577.093l-3.71 3.71-2.66-1.772a.5.5 0 0 0-.63.062L1.002 12V3a1 1 0 0 1 1-1h12z"/></svg>',
            //     onclick: (e) => {
            //         e.preventDefault();
            //         e.stopPropagation();
            //         this.toggleThumbnailPreview(e);
            //     }
            // }, buttonContainer);

            // 创建提取文案按钮
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: '提取视频文案',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M0 2a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.5a1 1 0 0 0-.8.4l-1.9 2.533a1 1 0 0 1-1.6 0L5.3 12.4a1 1 0 0 0-.8-.4H2a2 2 0 0 1-2-2V2zm7.194 2.766a1.688 1.688 0 0 0-.227-.272 1.467 1.467 0 0 0-.469-.324l-.008-.004A1.785 1.785 0 0 0 5.734 4C4.776 4 4 4.746 4 5.667c0 .92.776 1.666 1.734 1.666.343 0 .662-.095.931-.26-.137.389-.39.804-.81 1.22a.405.405 0 0 0 .011.59c.173.16.447.155.614-.01 1.334-1.329 1.37-2.758.941-3.706a2.461 2.461 0 0 0-.227-.4zM11 7.073c-.136.389-.39.804-.81 1.22a.405.405 0 0 0 .012.59c.172.16.446.155.613-.01 1.334-1.329 1.37-2.758.942-3.706a2.466 2.466 0 0 0-.228-.4 1.686 1.686 0 0 0-.227-.273 1.466 1.466 0 0 0-.469-.324l-.008-.004A1.785 1.785 0 0 0 10.07 4c-.957 0-1.734.746-1.734 1.667 0 .92.777 1.666 1.734 1.666.343 0 .662-.095.931-.26z"/></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.openTextExtractor(e);
                }
            }, buttonContainer);

            // 创建下载背景音乐按钮
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: '下载背景音乐',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M0 0h16v16H0z" fill="none"/><g fill="currentColor"><path d="M10 16v-5.401A2.999 2.999 0 0 0 10 5.4V0L4.667 4H0v8h4.667z"/><path d="m13.6 3.2l-.799-.6L11.6 4.199l.8.6a4 4 0 0 1 .8.802c.503.668.8 1.497.8 2.399s-.297 1.73-.8 2.4a4 4 0 0 1-.8.8l-.8.601l1.201 1.6l.8-.601a6 6 0 0 0 1.198-1.2A5.98 5.98 0 0 0 16 8c0-1.35-.447-2.598-1.2-3.6a6 6 0 0 0-1.2-1.2"/></g></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.downloadMusic(e);
                }
            }, buttonContainer);

            // 判断是否为图文：容器级检测 + 页面级 URL 兜底
            const isNotePage = isNote || this.isImageTextPage();

            // 创建下载视频/批量下载图片按钮
            // 始终走 batchDownloadImages，由该方法内部判断是否有图片
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: isNotePage ? '批量下载图片' : '下载视频',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14"><path fill="#fff" fill-rule="evenodd" d="M7 14A7 7 0 1 0 7 0a7 7 0 0 0 0 14m3.146-5.69l-2.793 2.793a.5.5 0 0 1-.707 0L3.854 8.31a.5.5 0 0 1 .353-.853H6V3.75a1 1 0 0 1 2 0v3.707h1.793a.5.5 0 0 1 .353.853" clip-rule="evenodd" /></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.batchDownloadImages(e);
                }
            }, buttonContainer);
        },

        // 为文章页面添加专属按钮
        addArticleButtons() {
            // 使用稳定的 leftContainer 类名定位（XJUH_Qra 等哈希类名会变动，leftContainer 不会变）
            const leftContainer = document.querySelector('.leftContainer');
            if (!leftContainer) return;

            // 如果已经添加过按钮则跳过
            if (leftContainer.querySelector('.dy-helper-buttons') || leftContainer.parentNode?.querySelector('.dy-helper-buttons')) {
                return;
            }

            const buttonContainer = elements.createAs('span', {
                className: 'dy-helper-buttons',
                style: `
                    display: inline-flex;
                    flex-direction: row;
                    gap: 10px;
                    vertical-align: middle;
                    margin-bottom: 10px;
                    z-index: 99999;
                `
            });
            // 将按钮容器插入到 leftContainer 内部的最上方（图标显示在标题上方）
            leftContainer.insertBefore(buttonContainer, leftContainer.firstChild);

            // 图标1：查看正文图片并下载
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: '查看正文图片并下载',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M6.002 5.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0z"/><path d="M2.002 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2h-12zm12 1a1 1 0 0 1 1 1v6.5l-3.777-1.947a.5.5 0 0 0-.577.093l-3.71 3.71-2.66-1.772a.5.5 0 0 0-.63.062L1.002 12V3a1 1 0 0 1 1-1h12z"/></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.viewArticleImages(e);
                }
            }, buttonContainer);

            // 图标2：复制全文
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: '复制全文',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M0 2a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.5a1 1 0 0 0-.8.4l-1.9 2.533a1 1 0 0 1-1.6 0L5.3 12.4a1 1 0 0 0-.8-.4H2a2 2 0 0 1-2-2V2zm7.194 2.766a1.688 1.688 0 0 0-.227-.272 1.467 1.467 0 0 0-.469-.324l-.008-.004A1.785 1.785 0 0 0 5.734 4C4.776 4 4 4.746 4 5.667c0 .92.776 1.666 1.734 1.666.343 0 .662-.095.931-.26-.137.389-.39.804-.81 1.22a.405.405 0 0 0 .011.59c.173.16.447.155.614-.01 1.334-1.329 1.37-2.758.941-3.706a2.461 2.461 0 0 0-.227-.4zM11 7.073c-.136.389-.39.804-.81 1.22a.405.405 0 0 0 .012.59c.172.16.446.155.613-.01 1.334-1.329 1.37-2.758.942-3.706a2.466 2.466 0 0 0-.228-.4 1.686 1.686 0 0 0-.227-.273 1.466 1.466 0 0 0-.469-.324l-.008-.004A1.785 1.785 0 0 0 10.07 4c-.957 0-1.734.746-1.734 1.667 0 .92.777 1.666 1.734 1.666.343 0 .662-.095.931-.26z"/></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.copyArticleText(e);
                }
            }, buttonContainer);

            // 图标3：下载全文为 MD
            elements.createAs('a', {
                href: 'javascript:void(0);',
                className: 'dy-icon-btn',
                title: '下载全文为 MD',
                innerHTML: '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14"><path fill="#fff" fill-rule="evenodd" d="M7 14A7 7 0 1 0 7 0a7 7 0 0 0 0 14m3.146-5.69l-2.793 2.793a.5.5 0 0 1-.707 0L3.854 8.31a.5.5 0 0 1 .353-.853H6V3.75a1 1 0 0 1 2 0v3.707h1.793a.5.5 0 0 1 .353.853" clip-rule="evenodd" /></svg>',
                onclick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.downloadArticleMd(e);
                }
            }, buttonContainer);
        },

        // 添加功能按钮悬浮窗
        addButtons() {
            if (!this.isVideoPage() && !this.isImageTextPage() && !this.isArticlePage()) {
                return;
            }

            // 文章页面：特殊处理
            if (this.isArticlePage()) {
                this.addArticleButtons();
                return;
            }

            // 查找所有可能的视频/图文容器 (针对 Feed 流和详情页)
            const videoContainers = document.querySelectorAll('[data-e2e="video-item"], .video-item, xg-video-container, #video-info-wrap, .video-info-detail, [data-e2e="note-item"], .note-item, .note-detail, [data-e2e="detail-video-info"]');

            if (videoContainers.length === 0) {
                // 回退方案：如果找不到明确的容器，直接全局查找时间或标题
                const fallbackContainers = document.querySelectorAll('.account-time, .video-info-time, [data-e2e="video-publish-time"], [data-e2e="video-time"], [data-e2e="video-desc"], [data-e2e="feed-video-desc"], h1[data-e2e="aweme-title"], .account-name, [data-e2e="note-title"], .note-title');
                fallbackContainers.forEach(container => this.injectButtonsTo(container));
            } else {
                videoContainers.forEach(container => {
                    // 详情页 (data-e2e="detail-video-info")：按钮放在标题后面
                    if (container.matches('[data-e2e="detail-video-info"]')) {
                        const titleEl = container.querySelector('h1[data-e2e="aweme-title"], [data-e2e="video-desc"], [data-e2e="feed-video-desc"], h1');
                        if (titleEl) {
                            this.injectButtonsTo(titleEl);
                        }
                        return;
                    }

                    // 优先查找时间元素 (覆盖 Feed 和 详情页的常见时间 class)
                    let targetEl = container.querySelector('.account-time, .video-info-time, [data-e2e="video-publish-time"], [data-e2e="video-time"], .time-info, span.time, .video-info-detail-time, [data-e2e="note-title"], .note-title');

                    // 如果没有时间元素，回退到查找标题或作者名称
                    if (!targetEl) {
                        targetEl = container.querySelector('[data-e2e="video-desc"], [data-e2e="feed-video-desc"], h1[data-e2e="aweme-title"], .account-name, [data-e2e="note-title"], .note-title');
                    }

                    if (targetEl) {
                        this.injectButtonsTo(targetEl);
                    }
                });
            }

        },

        // 显示缩略图预览
        async showThumbnailPreview(event) {
            const target = event.currentTarget;
            const thumbnailUrl = await this.getThumbnailUrl(target);
            if (thumbnailUrl) {
                preview.src = thumbnailUrl;
                const rect = target.getBoundingClientRect();

                // 预览图显示在按钮下方或上方
        preview.style.left = rect.left + 'px';
        preview.style.right = 'auto';
        preview.style.bottom = '120px';
        preview.style.width = 'auto';
        preview.style.height = 'auto'
                preview.onload = () => {
                    const screenWidth = window.innerWidth * 0.4;
                    const screenHeight = window.innerHeight * 0.6;

                    if (preview.naturalWidth > screenWidth || preview.naturalHeight > screenHeight) {
                        const widthRatio = screenWidth / preview.naturalWidth;
                        const heightRatio = screenHeight / preview.naturalHeight;
                        const ratio = Math.min(widthRatio, heightRatio);
                        preview.style.width = (preview.naturalWidth * ratio) + 'px';
                        preview.style.height = (preview.naturalHeight * ratio) + 'px';
                    }

                    const previewRect = preview.getBoundingClientRect();
                    if (previewRect.bottom > window.innerHeight) {
                        preview.style.top = (rect.top - previewRect.height - 10) + 'px';
                    }

                    preview.style.display = 'block';
                };
            }
        },

        // 隐藏缩略图预览
        hideThumbnailPreview() {
            preview.style.display = 'none';
        },

        // 点击切换缩略图预览的显示与隐藏
        async toggleThumbnailPreview(event) {
            if (preview.style.display === 'block') {
                this.hideThumbnailPreview();
            } else {
                const target = event.currentTarget;
                const thumbnailUrl = await this.getThumbnailUrl(target);
                if (thumbnailUrl) {
                    this.showThumbnailPreview(event);
                } else {
                    this.showToast('无法获取视频封面');
                }
            }
        },

        // 打开提取文案工具
        openTextExtractor(event) {
            const target = event ? event.currentTarget : null;
            const awemeId = this.getAwemeId(target);
            const currentUrl = awemeId ? `https://www.douyin.com/video/${awemeId}` : window.location.href;

            // 保存视频链接，供文案提取页面自动化使用
            try { GM_setValue('dy_tts_video_url', currentUrl); } catch (e) {}

            navigator.clipboard.writeText(currentUrl).then(() => {
                this.showToast('已复制视频地址，正在打开文案提取页面!');
                setTimeout(() => {
                    window.open('https://tts.byylook.com/ai/text-to-speech', '_blank');
                }, 500);
            }).catch(err => {
                console.error('复制失败:', err);
                this.showToast('前往文案提取页面');
                window.open('https://tts.byylook.com/ai/text-to-speech', '_blank');
            });
        },

        // 清理按钮
        cleanupButtons() {
            const containers = document.querySelectorAll('.dy-helper-buttons');
            containers.forEach(container => container.remove());
        },

        // 启动按钮检查
        startButtonCheck() {
            if (this.buttonCheckInterval) {
                clearInterval(this.buttonCheckInterval);
            }

            this.buttonCheckInterval = setInterval(() => {
                if (this.isVideoPage() || this.isImageTextPage() || this.isArticlePage()) {
                    this.addButtons();
                } else {
                    this.cleanupButtons();
                }
            }, 500);
        },

        // 初始化
        init() {
            this.addButtons();
            this.startButtonCheck();
            console.log('抖音浏览助手初始化成功');

            let lastUrl = location.href;
            new MutationObserver(() => {
                if (lastUrl !== location.href) {
                    lastUrl = location.href;
                    setTimeout(() => {
                        this.addButtons();
                    }, 1000);
                }
            }).observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    };

    // 等待页面加载完成后初始化（立即执行，图标第一时间显示）
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            douyinViewer.init();
        });
    } else {
        douyinViewer.init();
    }
})();