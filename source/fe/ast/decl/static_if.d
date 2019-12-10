/// Copyright: Copyright (c) 2017-2019 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module fe.ast.decl.static_if;

import all;


@(AstType.decl_static_if)
struct StaticIfDeclNode
{
	mixin AstNodeData!(AstType.decl_static_if, AstFlags.isDeclaration);
	AstIndex condition;
	AstNodes thenItems; // can be empty
	AstNodes elseItems; // can be empty
	AstIndex next;
	AstIndex prev;
	// index into AstNodes of the parent node
	uint arrayIndex;
}

void name_register_nested_static_if(AstIndex nodeIndex, StaticIfDeclNode* node, ref NameRegisterState state) {
	node.state = AstNodeState.name_register_nested;
	require_name_register(node.condition, state);
	node.state = AstNodeState.name_register_nested_done;
}