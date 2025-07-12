// AutoDismissFlash Phoenix LiveView Hook
export const AutoDismissFlash = {
  mounted() {
    // Auto-dismiss flash messages after 2 seconds
    setTimeout(() => {
      this.el.style.transition = 'opacity 0.3s ease-out';
      this.el.style.opacity = '0';
      setTimeout(() => {
        // Trigger the existing Phoenix flash clearing mechanism
        this.el.click();
      }, 300); // Wait for fade out animation
    }, 2000);
  }
};

// ViewportResize Phoenix LiveView Hook
export const ViewportResize = {
  mounted() {
    this.handleResize = this.handleResize.bind(this);
    window.addEventListener('resize', this.handleResize);
    // Send initial size
    this.handleResize();
  },
  
  destroyed() {
    window.removeEventListener('resize', this.handleResize);
  },
  
  handleResize() {
    this.pushEvent('viewport_resize', {
      width: window.innerWidth,
      height: window.innerHeight
    });
  }
};

// SynthCanvas Phoenix LiveView Hook
export const SynthCanvas = {
  mounted() {
    this.isDragging = false;
    this.dragTarget = null;
    this.dragOffset = { x: 0, y: 0 };
    this.svg = this.el;
    
    // Add event listeners for drag and drop
    this.handleMouseDown = this.handleMouseDown.bind(this);
    this.handleMouseMove = this.handleMouseMove.bind(this);
    this.handleMouseUp = this.handleMouseUp.bind(this);
    this.handleRightClick = this.handleRightClick.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
    
    this.svg.addEventListener('mousedown', this.handleMouseDown);
    this.svg.addEventListener('contextmenu', this.handleRightClick);
    document.addEventListener('mousemove', this.handleMouseMove);
    document.addEventListener('mouseup', this.handleMouseUp);
    document.addEventListener('keydown', this.handleKeyDown);
    
    // Prevent default drag behavior on SVG elements
    this.svg.addEventListener('dragstart', (e) => e.preventDefault());
  },
  
  destroyed() {
    this.svg.removeEventListener('mousedown', this.handleMouseDown);
    this.svg.removeEventListener('contextmenu', this.handleRightClick);
    document.removeEventListener('mousemove', this.handleMouseMove);
    document.removeEventListener('mouseup', this.handleMouseUp);
    document.removeEventListener('keydown', this.handleKeyDown);
  },
  
  handleMouseDown(e) {
    // Check if we clicked on a port (skip dragging for ports)
    if (e.target.closest('g[phx-click="port_clicked"]') || 
        e.target.closest('g[phx-click="connection_delete"]')) {
      return;
    }
    
    // Check if we clicked on a node
    const nodeGroup = e.target.closest('g[id^="node-"]');
    if (!nodeGroup) return;
    
    e.preventDefault();
    e.stopPropagation();
    
    this.isDragging = true;
    this.dragTarget = nodeGroup;
    
    // Get the current transform of the node
    const transform = nodeGroup.getAttribute('transform');
    const match = transform.match(/translate\(([^,]+),([^)]+)\)/);
    const currentX = match ? parseFloat(match[1]) : 0;
    const currentY = match ? parseFloat(match[2]) : 0;
    
    // Get mouse position relative to SVG
    const rect = this.svg.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Calculate offset from mouse to node position
    this.dragOffset = {
      x: mouseX - currentX,
      y: mouseY - currentY
    };
    
    // Add visual feedback
    nodeGroup.style.opacity = '0.8';
  },
  
  handleMouseMove(e) {
    if (!this.isDragging || !this.dragTarget) return;
    
    e.preventDefault();
    
    // Get mouse position relative to SVG
    const rect = this.svg.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Calculate new position with dynamic node height (minimum 80px)
    const nodeHeight = 80; // Default height, dynamic height calculation would need server communication
    const nodeWidth = 140; // Default node width
    const newX = Math.max(0, Math.min(mouseX - this.dragOffset.x, this.svg.viewBox.baseVal.width - nodeWidth));
    const newY = Math.max(0, Math.min(mouseY - this.dragOffset.y, this.svg.viewBox.baseVal.height - nodeHeight));
    
    // Update node position
    this.dragTarget.setAttribute('transform', `translate(${newX}, ${newY})`);
  },
  
  handleMouseUp(e) {
    if (!this.isDragging || !this.dragTarget) return;
    
    e.preventDefault();
    
    // Get final position
    const transform = this.dragTarget.getAttribute('transform');
    const match = transform.match(/translate\(([^,]+),([^)]+)\)/);
    const finalX = match ? parseFloat(match[1]) : 0;
    const finalY = match ? parseFloat(match[2]) : 0;
    
    // Get node ID from the group element
    const nodeId = this.dragTarget.id.replace('node-', '');
    
    // Send position update to LiveView
    this.pushEvent('node_moved', {
      id: parseInt(nodeId),
      x: finalX,
      y: finalY
    });
    
    // Remove visual feedback
    this.dragTarget.style.opacity = '1';
    
    // Reset drag state
    this.isDragging = false;
    this.dragTarget = null;
    this.dragOffset = { x: 0, y: 0 };
  },

  handleRightClick(e) {
    e.preventDefault();
    e.stopPropagation();

    // Check if we right-clicked on a node
    const nodeGroup = e.target.closest('g[id^="node-"]');
    
    // Get click position relative to the viewport
    const x = e.clientX;
    const y = e.clientY;

    if (nodeGroup) {
      // Right-click on node - show node context menu
      const nodeId = nodeGroup.id.replace('node-', '');
      
      this.pushEvent('show_context_menu', {
        node_id: parseInt(nodeId),
        x: x,
        y: y
      });
    } else {
      // Right-click on background - show node creation menu
      // Get position relative to SVG for node placement
      const rect = this.svg.getBoundingClientRect();
      const svgX = e.clientX - rect.left;
      const svgY = e.clientY - rect.top;
      
      this.pushEvent('show_node_creation_menu', {
        x: x,  // Viewport position for menu placement
        y: y,
        svg_x: svgX,  // SVG position for node creation
        svg_y: svgY
      });
    }
  },

  handleKeyDown(e) {
    // Enable keyboard shortcuts for better navigation
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
      return; // Don't interfere with input fields
    }
    
    const container = document.getElementById('canvas-container');
    if (!container) return;
    
    switch(e.key) {
      case 'ArrowUp':
        e.preventDefault();
        container.scrollTop = Math.max(0, container.scrollTop - 50);
        break;
      case 'ArrowDown':
        e.preventDefault();
        container.scrollTop = Math.min(container.scrollHeight - container.clientHeight, container.scrollTop + 50);
        break;
      case 'ArrowLeft':
        e.preventDefault();
        container.scrollLeft = Math.max(0, container.scrollLeft - 50);
        break;
      case 'ArrowRight':
        e.preventDefault();
        container.scrollLeft = Math.min(container.scrollWidth - container.clientWidth, container.scrollLeft + 50);
        break;
      case 'Home':
        e.preventDefault();
        container.scrollTop = 0;
        container.scrollLeft = 0;
        break;
    }
  }
};

// ConstKnob Phoenix LiveView Hook for knob value controls
export const ConstKnob = {
  mounted() {
    this.isDragging = false;
    this.startY = 0;
    this.startValue = 0;
    this.nodeId = parseInt(this.el.dataset.nodeId);
    this.currentVal = parseFloat(this.el.dataset.currentVal);
    this.minVal = parseFloat(this.el.dataset.minVal);
    this.maxVal = parseFloat(this.el.dataset.maxVal);
    
    // Bind event handlers
    this.handleMouseDown = this.handleMouseDown.bind(this);
    this.handleMouseMove = this.handleMouseMove.bind(this);
    this.handleMouseUp = this.handleMouseUp.bind(this);
    
    // Add event listeners
    this.el.addEventListener('mousedown', this.handleMouseDown);
    document.addEventListener('mousemove', this.handleMouseMove);
    document.addEventListener('mouseup', this.handleMouseUp);
  },
  
  destroyed() {
    this.el.removeEventListener('mousedown', this.handleMouseDown);
    document.removeEventListener('mousemove', this.handleMouseMove);
    document.removeEventListener('mouseup', this.handleMouseUp);
  },
  
  handleMouseDown(e) {
    e.preventDefault();
    e.stopPropagation();
    
    this.isDragging = true;
    this.startY = e.clientY;
    this.startValue = this.currentVal;
    
    // Visual feedback
    this.el.style.opacity = '0.8';
  },
  
  handleMouseMove(e) {
    if (!this.isDragging) return;
    
    e.preventDefault();
    
    // Calculate value change based on vertical mouse movement
    // Moving up increases value, moving down decreases
    const deltaY = this.startY - e.clientY; // Invert so up = positive
    const sensitivity = (this.maxVal - this.minVal) / 100; // 100 pixels for full range
    const newValue = this.startValue + (deltaY * sensitivity);
    
    // Clamp value to min/max range
    const clampedValue = Math.max(this.minVal, Math.min(this.maxVal, newValue));
    
    // Update current value for real-time feedback
    this.currentVal = clampedValue;
    
    // Send update to LiveView
    this.pushEvent('update_const_value', {
      node_id: this.nodeId,
      value: clampedValue
    });
  },
  
  handleMouseUp(e) {
    if (!this.isDragging) return;
    
    e.preventDefault();
    
    this.isDragging = false;
    
    // Remove visual feedback
    this.el.style.opacity = '1';
  }
};