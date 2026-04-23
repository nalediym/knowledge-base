(function () {
  'use strict';

  var svg = document.getElementById('graph');
  var tooltip = document.getElementById('tooltip');
  var statusText = document.getElementById('status-text');
  var meta = document.getElementById('meta');
  var SVG_NS = 'http://www.w3.org/2000/svg';

  var state = {
    nodes: [],
    edges: [],
    sim: null,
    elements: { edges: {}, nodes: {} },
    byId: {}
  };

  function colorFor(kind) {
    return {
      source: 'var(--source)',
      concept: 'var(--concept)',
      candidate: 'var(--candidate)',
      stale: 'var(--stale)'
    }[kind] || 'var(--muted)';
  }

  function clearSvg() {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
  }

  function render() {
    clearSvg();
    state.elements = { edges: {}, nodes: {} };

    var gEdges = document.createElementNS(SVG_NS, 'g');
    gEdges.setAttribute('class', 'edges');
    svg.appendChild(gEdges);

    var gNodes = document.createElementNS(SVG_NS, 'g');
    gNodes.setAttribute('class', 'nodes');
    svg.appendChild(gNodes);

    state.sim.edges.forEach(function (e) {
      var line = document.createElementNS(SVG_NS, 'line');
      line.setAttribute('stroke', 'var(--edge)');
      line.setAttribute('stroke-width', '1');
      gEdges.appendChild(line);
      state.elements.edges[e.raw.from + '|' + e.raw.to] = line;
    });

    state.sim.nodes.forEach(function (n) {
      var g = document.createElementNS(SVG_NS, 'g');
      g.setAttribute('class', 'node');
      g.setAttribute('data-id', n.id);
      g.style.cursor = 'pointer';

      var circle = document.createElementNS(SVG_NS, 'circle');
      circle.setAttribute('r', n.kind === 'candidate' ? 6 : 8);
      circle.setAttribute('fill', colorFor(n.kind));
      circle.setAttribute('stroke', '#0f1117');
      circle.setAttribute('stroke-width', '1.5');
      g.appendChild(circle);

      var label = document.createElementNS(SVG_NS, 'text');
      label.textContent = n.label;
      label.setAttribute('x', 12);
      label.setAttribute('y', 4);
      label.setAttribute('font-size', '11');
      label.setAttribute('fill', '#cbd0e0');
      g.appendChild(label);

      g.addEventListener('mouseenter', function (ev) { showTooltip(n, ev); });
      g.addEventListener('mousemove', function (ev) { moveTooltip(ev); });
      g.addEventListener('mouseleave', hideTooltip);
      g.addEventListener('click', function () { openFile(n); });

      gNodes.appendChild(g);
      state.elements.nodes[n.id] = g;
    });

    updateMeta();
    animate();
  }

  function animate() {
    for (var i = 0; i < 3; i++) state.sim.tick();
    state.sim.edges.forEach(function (e) {
      var el = state.elements.edges[e.raw.from + '|' + e.raw.to];
      if (!el) return;
      el.setAttribute('x1', e.source.x);
      el.setAttribute('y1', e.source.y);
      el.setAttribute('x2', e.target.x);
      el.setAttribute('y2', e.target.y);
    });
    state.sim.nodes.forEach(function (n) {
      var el = state.elements.nodes[n.id];
      if (el) el.setAttribute('transform', 'translate(' + n.x + ',' + n.y + ')');
    });
    requestAnimationFrame(animate);
  }

  function updateMeta() {
    var counts = { source: 0, concept: 0, candidate: 0, stale: 0 };
    state.nodes.forEach(function (n) { counts[n.kind] = (counts[n.kind] || 0) + 1; });
    meta.textContent =
      state.nodes.length + ' nodes · ' + state.edges.length + ' edges · ' +
      counts.source + ' src · ' + counts.concept + ' con · ' +
      counts.candidate + ' cand · ' + counts.stale + ' stale';
  }

  function showTooltip(n, ev) {
    var cites = [];
    state.edges.forEach(function (e) {
      if ((e.from === n.id || e.to === n.id) && e.citations && e.citations.length) {
        cites = cites.concat(e.citations);
      }
    });
    cites = cites.filter(function (v, i, a) { return a.indexOf(v) === i; });

    var html = '<div class="kind">' + n.kind + '</div>' +
      '<h4>' + escapeHtml(n.label) + '</h4>' +
      (n.path ? '<div style="color:var(--muted);font-size:11px">' + escapeHtml(n.path) + '</div>' : '') +
      (cites.length
        ? '<ul>' + cites.slice(0, 8).map(function (c) { return '<li>' + escapeHtml(c) + '</li>'; }).join('') + '</ul>'
        : '<div style="color:var(--muted);font-size:11px;margin-top:4px">no citations</div>');
    tooltip.innerHTML = html;
    tooltip.style.display = 'block';
    moveTooltip(ev);
  }

  function moveTooltip(ev) {
    tooltip.style.left = (ev.clientX + 14) + 'px';
    tooltip.style.top = (ev.clientY + 14) + 'px';
  }

  function hideTooltip() { tooltip.style.display = 'none'; }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function openFile(n) {
    if (!n.path) return;
    fetch('/open', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: n.id })
    });
  }

  function initFromGraph(g) {
    state.nodes = g.nodes;
    state.edges = g.edges;
    state.byId = {};
    g.nodes.forEach(function (n) { state.byId[n.id] = n; });
    state.sim = KbForce.create(
      g.nodes.map(function (n) { return Object.assign({}, n); }),
      g.edges,
      { width: window.innerWidth, height: window.innerHeight }
    );
    svg.setAttribute('width', window.innerWidth);
    svg.setAttribute('height', window.innerHeight);
    render();
  }

  function applyDelta(delta) {
    var changed = false;
    (delta.add_nodes || []).forEach(function (n) {
      if (!state.byId[n.id]) {
        state.nodes.push(n);
        state.byId[n.id] = n;
        changed = true;
      }
    });
    (delta.add_edges || []).forEach(function (e) {
      state.edges.push(e);
      changed = true;
    });
    if (changed) {
      // rebuild sim preserving positions
      var positions = {};
      state.sim.nodes.forEach(function (n) { positions[n.id] = { x: n.x, y: n.y }; });
      state.sim = KbForce.create(
        state.nodes.map(function (n) {
          var p = positions[n.id] || {};
          return Object.assign({}, n, { x: p.x, y: p.y });
        }),
        state.edges,
        { width: window.innerWidth, height: window.innerHeight }
      );
      render();
    }
  }

  function connectSSE() {
    if (!window.EventSource) {
      statusText.textContent = 'SSE unsupported';
      return;
    }
    var es = new EventSource('/events');
    es.onopen = function () { statusText.textContent = 'live'; };
    es.onerror = function () { statusText.textContent = 'reconnecting…'; };
    es.addEventListener('delta', function (ev) {
      try { applyDelta(JSON.parse(ev.data)); } catch (_) {}
    });
    es.addEventListener('replace', function (ev) {
      try { initFromGraph(JSON.parse(ev.data)); } catch (_) {}
    });
    es.addEventListener('ping', function () { /* keepalive */ });
  }

  window.addEventListener('resize', function () {
    svg.setAttribute('width', window.innerWidth);
    svg.setAttribute('height', window.innerHeight);
    if (state.sim) state.sim.resize(window.innerWidth, window.innerHeight);
  });

  fetch('/graph.json')
    .then(function (r) { return r.json(); })
    .then(function (g) {
      initFromGraph(g);
      connectSSE();
    })
    .catch(function (e) {
      statusText.textContent = 'error: ' + e.message;
    });
})();
