"""红黑树核心实现"""

from typing import Any, Optional, Generic, TypeVar, Callable, Iterator
from enum import Enum
import uuid

T = TypeVar('T')


class Color(Enum):
    RED = 'red'
    BLACK = 'black'


class Node(Generic[T]):
    def __init__(self, key: T, value: Any, left: Optional['Node'] = None,
                 right: Optional['Node'] = None, parent: Optional['Node'] = None,
                 color: Color = Color.RED):
        self.key = key
        self.value = value
        self.left = left
        self.right = right
        self.parent = parent
        self.color = color


class RedBlackTree(Generic[T]):
    """Python 红黑树实现
    
    性质：
    1. 节点要么是红色，要么是黑色
    2. 根节点是黑色
    3. 叶子节点（NIL）是黑色
    4. 红色节点的子节点必须是黑色
    5. 从根到叶子节点的所有路径包含相同数量的黑色节点
    """
    
    def __init__(self, comparator: Optional[Callable[[T, T], int]] = None):
        self.root: Optional[Node] = None
        self._comparator = comparator or (lambda a, b: (a > b) - (a < b))
    
    def _get_color(self, node: Optional[Node]) -> Color:
        return Color.BLACK if node is None else node.color
    
    def _get_parent(self, node: Optional[Node]) -> Optional[Node]:
        return node.parent if node else None
    
    def _insert(self, key: T, value: Any):
        """插入新节点"""
        if self.root is None:
            self.root = Node(key, value, color=Color.BLACK)
            return
        
        # 查找插入位置
        node = self.root
        parent = None
        while node:
            parent = node
            if self._comparator(key, node.key) < 0:
                node = node.left
            else:
                node = node.right
        
        # 创建新节点
        new_node = Node(key, value, parent=parent)
        if self._comparator(key, parent.key) < 0:
            parent.left = new_node
        else:
            parent.right = new_node
        
        # 修复红黑树性质
        self._fix_after_insert(new_node)
    
    def _fix_after_insert(self, node: Node):
        """插入后的修复算法"""
        while self._get_parent(node) and self._get_parent(node).color == Color.RED:
            parent = self._get_parent(node)
            grandparent = self._get_parent(parent)
            
            if parent == grandparent.left:
                uncle = grandparent.right
                
                if uncle and uncle.color == Color.RED:
                    # 情况 1：叔父节点是红色
                    parent.color = Color.BLACK
                    uncle.color = Color.BLACK
                    grandparent.color = Color.RED
                    node = grandparent
                else:
                    # 情况 2：叔父节点是黑色
                    if parent.right and parent.right.key == node.key:
                        # 情况 2a：右孩子插入，先左旋
                        self._left_rotate(grandparent)
                        parent = grandparent.right
                        grandparent = self._get_parent(parent)
                        node = parent
                    
                    if parent.left and parent.left.key == node.key:
                        # 情况 2b：左孩子插入，先右旋
                        self._right_rotate(grandparent)
                        parent = grandparent.left
                        grandparent = self._get_parent(parent)
                        node = parent
                    
                    # 情况 2c：重新着色
                    parent.color = Color.BLACK
                    grandparent.color = Color.RED
                    if node.parent:
                        node.parent.color = Color.RED
            else:
                # 对称情况
                uncle = grandparent.left
                
                if uncle and uncle.color == Color.RED:
                    parent.color = Color.BLACK
                    uncle.color = Color.BLACK
                    grandparent.color = Color.RED
                    node = grandparent
                else:
                    if parent.left and parent.left.key == node.key:
                        self._right_rotate(grandparent)
                        parent = grandparent.left
                        grandparent = self._get_parent(parent)
                        node = parent
                    
                    if parent.right and parent.right.key == node.key:
                        self._left_rotate(grandparent)
                        parent = grandparent.right
                        grandparent = self._get_parent(parent)
                        node = parent
                    
                    parent.color = Color.BLACK
                    grandparent.color = Color.RED
                    if node.parent:
                        node.parent.color = Color.RED
        
        self.root.color = Color.BLACK
    
    def _left_rotate(self, node: Node):
        """左旋"""
        right_child = node.right
        node.right = right_child.left
        if right_child.left:
            right_child.left.parent = node
        right_child.parent = node.parent
        
        if node.parent:
            if node == node.parent.left:
                node.parent.left = right_child
            else:
                node.parent.right = right_child
        
        right_child.left = node
        node.parent = right_child
    
    def _right_rotate(self, node: Node):
        """右旋"""
        left_child = node.left
        node.left = left_child.right
        if left_child.right:
            left_child.right.parent = node
        left_child.parent = node.parent
        
        if node.parent:
            if node == node.parent.left:
                node.parent.left = left_child
            else:
                node.parent.right = left_child
        
        left_child.right = node
        node.parent = left_child
    
    def search(self, key: T) -> Optional[Any]:
        """查找值"""
        node = self.root
        while node:
            cmp = self._comparator(key, node.key)
            if cmp < 0:
                node = node.left
            elif cmp > 0:
                node = node.right
            else:
                return node.value
        return None
    
    def insert(self, key: T, value: Any) -> bool:
        """插入键值对，返回是否成功插入"""
        if self.search(key) is not None:
            return False
        self._insert(key, value)
        return True
    
    def delete(self, key: T):
        """删除节点"""
        node = self._find_node(key)
        if not node:
            return
        
        self._delete_node(node)
    
    def _find_node(self, key: T) -> Optional[Node]:
        """查找节点"""
        node = self.root
        while node:
            cmp = self._comparator(key, node.key)
            if cmp < 0:
                node = node.left
            elif cmp > 0:
                node = node.right
            else:
                return node
        return None
    
    def _delete_node(self, node: Node):
        """删除节点并修复红黑树"""
        successor = None
        node_to_delete = node
        
        # 查找后继节点
        if node.right:
            while node.right.left:
                node.right = node.right.left
                node = node.right
            successor = node.right
        elif node.left:
            successor = node.left
        else:
            successor = None
        
        # 获取父节点
        parent = self._get_parent(node)
        grandparent = self._get_parent(parent)
        
        # 连接后继节点
        if successor:
            successor.parent = parent
        
        # 处理不同情况
        if node == self.root:
            self.root = successor
            if successor:
                successor.parent = None
                successor.color = Color.BLACK
        else:
            if successor:
                parent.left if parent.left == node else parent.right = successor
            else:
                parent.left if parent.left == node else parent.right = None
        
        if node.color == Color.BLACK:
            self._fix_after_delete(grandparent if grandparent else None,
                               successor if successor else None)
    
    def _fix_after_delete(self, grandparent: Optional[Node], successor: Optional[Node]):
        """删除后的修复"""
        if not grandparent:
            return
        
        sibling = grandparent.right if grandparent.left == successor else grandparent.left
        
        while (grandparent != self.root and 
               (not successor or successor.color == Color.BLACK) and
               (not sibling or sibling.color == Color.BLACK)):
            
            if grandparent.left == successor:
                # 兄弟在右侧
                if sibling.color == Color.RED:
                    sibling.color = Color.BLACK
                    grandparent.color = Color.RED
                    self._left_rotate(grandparent)
                    sibling = grandparent.right
                
                if (not grandparent.right or 
                    grandparent.right.color == Color.BLACK and 
                    (not grandparent.right.left or grandparent.right.left.color == Color.BLACK) and
                    (not grandparent.right.right or grandparent.right.right.color == Color.BLACK)):
                    sibling.color = Color.RED
                    grandparent.color = Color.BLACK
                    self._right_rotate(grandparent)
                    continue
                
                if grandparent.right.right and grandparent.right.right.color == Color.RED:
                    grandparent.right.color = Color.BLACK
                    grandparent.color = Color.RED
                    self._right_rotate(grandparent.right)
                    sibling = grandparent.right
                
                sibling.color = grandparent.color
                grandparent.color = Color.BLACK
                if sibling:
                    sibling.left.color = Color.BLACK
            else:
                # 兄弟在左侧
                if sibling.color == Color.RED:
                    sibling.color = Color.BLACK
                    grandparent.color = Color.RED
                    self._right_rotate(grandparent)
                    sibling = grandparent.left
                
                if (not grandparent.left or 
                    grandparent.left.color == Color.BLACK and 
                    (not grandparent.left.left or grandparent.left.left.color == Color.BLACK) and
                    (not grandparent.left.right or grandparent.left.right.color == Color.BLACK)):
                    sibling.color = Color.RED
                    grandparent.color = Color.BLACK
                    self._left_rotate(grandparent)
                    continue
                
                if grandparent.left.left and grandparent.left.left.color == Color.RED:
                    grandparent.left.color = Color.BLACK
                    grandparent.color = Color.RED
                    self._left_rotate(grandparent.left)
                    sibling = grandparent.left
                
                sibling.color = grandparent.color
                grandparent.color = Color.BLACK
                if sibling:
                    sibling.right.color = Color.BLACK
        
        if successor and successor.color == Color.RED:
            successor.color = Color.BLACK
        
        if grandparent and grandparent.color == Color.RED:
            grandparent.color = Color.BLACK
    
    def min(self) -> Optional[T]:
        """获取最小键值"""
        if not self.root:
            return None
        node = self.root
        while node.left:
            node = node.left
        return node.key
    
    def max(self) -> Optional[T]:
        """获取最大键值"""
        if not self.root:
            return None
        node = self.root
        while node.right:
            node = node.right
        return node.key
    
    def inorder_traverse(self, callback: Callable[[Node], None] = None):
        """中序遍历"""
        stack = []
        current = self.root
        
        while stack or current:
            if current:
                stack.append(current)
                current = current.left
            else:
                node = stack.pop()
                if callback:
                    callback(node)
                current = node.right
    
    def preorder_traverse(self, callback: Callable[[Node], None] = None):
        """前序遍历"""
        if not self.root:
            return
        stack = [self.root]
        while stack:
            node = stack.pop()
            if callback:
                callback(node)
            if node.right:
                stack.append(node.right)
            if node.left:
                stack.append(node.left)
    
    def get_height(self) -> int:
        """获取树高"""
        if not self.root:
            return 0
        return self._get_height(self.root)
    
    def _get_height(self, node: Optional[Node]) -> int:
        if not node:
            return 0
        left_h = self._get_height(node.left)
        right_h = self._get_height(node.right)
        return max(left_h, right_h) + 1
    
    def get_size(self) -> int:
        """获取节点数量"""
        count = 0
        stack = [self.root]
        while stack:
            node = stack.pop()
            if node.left:
                stack.append(node.left)
            if node.right:
                stack.append(node.right)
            count += 1
        return count
    
    def to_dict(self) -> dict:
        """转换为字典"""
        result = {}
        self.preorder_traverse(lambda node: result.setdefault(node.key, node.value))
        return result
    
    def __contains__(self, key: T) -> bool:
        return self.search(key) is not None
    
    def __iter__(self) -> Iterator[T]:
        return iter(self.inorder_traverse())
    
    def __len__(self) -> int:
        return self.get_size()


if __name__ == "__main__":
    # 测试红黑树
    tree = RedBlackTree()
    
    # 插入一些数据
    for i in range(1, 11):
        tree.insert(i, f'value_{i}')
    
    print("插入完成，树高:", tree.get_height())
    print("最小值:", tree.min())
    print("最大值:", tree.max())
    print("节点数:", len(tree))
    print("字典表示:", tree.to_dict())
    
    # 验证中序遍历有序
    print("中序遍历:", [tree.search(i) for i in range(1, 11)])
