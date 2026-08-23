import { Component } from 'react';

class TodoList extends Component {
    render() {
        return (
            <div className="todo-page">
                <style>{`
                    /* ===== WRITE YOUR CSS HERE ===== */

                    .todo-page {
                        font-family: Arial, sans-serif;
                        padding: 20px;
                    }

                    h1 {
                        font-size: 24px;
                    }
                `}</style>

                {/* ===== WRITE YOUR HTML HERE ===== */}

                <h1>to do</h1>
                <h1>things done</h1>

            </div>
        );
    }
}

export default TodoList;
