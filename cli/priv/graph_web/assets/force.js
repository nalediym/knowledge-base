// Minimal 2D force-directed layout. No external deps. Deterministic enough
// for interactive use; runs a fixed number of ticks then idles until the
// graph changes. Exposes `KbForce.create(nodes, edges, opts)`.
(function () {
  'use strict';

  function create(nodes, edges, opts) {
    opts = opts || {};
    var width = opts.width || 960;
    var height = opts.height || 720;
    var link = opts.linkDistance || 90;
    var charge = opts.charge || -160;
    var gravity = opts.gravity || 0.02;
    var friction = opts.friction || 0.85;

    // initialize random positions within viewport
    var byId = {};
    nodes.forEach(function (n) {
      if (n.x == null) n.x = (Math.random() - 0.5) * width * 0.8 + width / 2;
      if (n.y == null) n.y = (Math.random() - 0.5) * height * 0.8 + height / 2;
      n.vx = n.vx || 0;
      n.vy = n.vy || 0;
      byId[n.id] = n;
    });

    // resolve edge endpoints to node refs
    var resolvedEdges = edges.map(function (e) {
      return { source: byId[e.from], target: byId[e.to], raw: e };
    }).filter(function (e) { return e.source && e.target; });

    function tick() {
      // repulsion (O(n^2); fine for <500 nodes)
      for (var i = 0; i < nodes.length; i++) {
        var a = nodes[i];
        if (a.fixed) continue;
        for (var j = i + 1; j < nodes.length; j++) {
          var b = nodes[j];
          var dx = b.x - a.x;
          var dy = b.y - a.y;
          var dist2 = dx * dx + dy * dy + 0.01;
          var force = charge / dist2;
          var dist = Math.sqrt(dist2);
          var fx = (dx / dist) * force;
          var fy = (dy / dist) * force;
          a.vx -= fx;
          a.vy -= fy;
          if (!b.fixed) {
            b.vx += fx;
            b.vy += fy;
          }
        }
      }

      // springs
      resolvedEdges.forEach(function (e) {
        var dx = e.target.x - e.source.x;
        var dy = e.target.y - e.source.y;
        var dist = Math.sqrt(dx * dx + dy * dy) || 0.01;
        var diff = (dist - link) / dist;
        var fx = dx * diff * 0.05;
        var fy = dy * diff * 0.05;
        if (!e.source.fixed) { e.source.vx += fx; e.source.vy += fy; }
        if (!e.target.fixed) { e.target.vx -= fx; e.target.vy -= fy; }
      });

      // gravity toward center + integrate
      nodes.forEach(function (n) {
        if (n.fixed) return;
        n.vx += (width / 2 - n.x) * gravity * 0.01;
        n.vy += (height / 2 - n.y) * gravity * 0.01;
        n.vx *= friction;
        n.vy *= friction;
        n.x += n.vx;
        n.y += n.vy;
      });
    }

    return {
      nodes: nodes,
      edges: resolvedEdges,
      tick: tick,
      resize: function (w, h) { width = w; height = h; }
    };
  }

  window.KbForce = { create: create };
})();
